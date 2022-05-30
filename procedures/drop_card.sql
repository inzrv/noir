# Исправлена транзакция + now_time()


drop procedure if exists drop_card;
create procedure drop_card(code varchar(10), user_name varchar(20), password varchar(10), name varchar(20))
drop_card: begin

    #для хранения id сбрасываемого
    declare id_dropped int;
    
    #для хранения id игры
    declare id_game int;

    #id данного игрока
    declare this_player_id int;

    #id соперника
    declare opp_id int;
    
    #время игрока
    declare player_time timestamp;
    
    #время противника
    declare opp_time timestamp;

    #время на ход в данной игре
    declare time_to_move time;

    #время последнего совершенного хода в данной игре
    declare last_move_time timestamp;

    # Текущее время. Будем получать его как можно ближе к вызову процедуры
    declare now_time timestamp default now(); 

    #проверка имени и пароля
    if user_check(user_name, password) = false then
        select 'Wrong login or password!' as Error;
        leave drop_card;
    end if;
    
    #проверка кода комнаты
    if code_check(code) = false then
        select 'Wrong game code' as Error;
        leave drop_card;
    end if;

    set transaction isolation level READ COMMITTED;
    start transaction;

    # Если удалим игрока раньше, чем эта строка, то выдаст ошибку 'You are not a member of this game'
    # Получаем id игроков и игры

    set id_game = get_game_id(code);
    do (select count(*) from Games where Games.id = id_game for update);

    set this_player_id = get_player_id(id_game, user_name);
    do (select count(*) from Players where Players.id = this_player_id for update);

    if (this_player_id in (select Games.id_creator from Games where Games.id = id_game)) then
        set opp_id = (select Games.id_connected from Games where Games.id = id_game);
    else 
        set opp_id = (select Games.id_creator from Games where Games.id = id_game);
    end if;
    do (select count(*) from Players where Players.id = opp_id for update);

    # my_char() ждет конца транзакции и выводит информацию после сброса

    if this_player_id = 0 then
        commit;
        select 'You are not a member of this game' as Error;
        leave drop_card;
    end if;
    
    #если пользователь один в игре
    if opp_id is NULL then
        commit;
       select 'You cannot play alone' as Error;
       leave drop_card;
    end if;
    
    #проверка пользователя на полицейского
    if this_player_id not in (select id from Policemen) then
        commit;
        select 'You are not a cop!' as Error;
        leave drop_card;
    end if;
    
    #данный ход может быть сделан только после призыва к присяге
    if (select last_move_command(id_game)) != 'oath' then
        commit;
        select 'You cannot make this move now' as Error;
        leave drop_card;
    end if;
    
    #получаем id сбрасываемой карты
    set id_dropped = (select Characters.id from Characters 
        join Uniformed_officers on Uniformed_officers.id_character = Characters.id
        join Names on Names.id = Characters.id_name
        where Characters.id_game = id_game and name = Names.name);
    
    #попыка сбросить карты, которой у игрока нет
    if id_dropped is NULL then
        commit;
        select 'You cannot drop this character' as Error;
        leave drop_card;
    end if;
    
    #проверка времени
    set time_to_move = (select Games.time_to_move from Games where Games.id = id_game);
    set player_time = (select Players.turn_time from Players where Players.id = this_player_id);
    set opp_time = (select Players.turn_time from Players where Players.id = opp_id);

    #запоминаем, чей ход был последним
    if (player_time > opp_time) then
        set last_move_time = player_time;
    else
        set last_move_time = opp_time;
    end if;
    
    if ((last_move_time = opp_time and can_move(last_move_time, time_to_move, now_time)) or
        (last_move_time = player_time and not can_move(last_move_time, time_to_move, now_time) 
        and timediff(now_time, last_move_time) > time_to_move))
    then
        #если можем сделать ход, то обновляем информацию
        update Games set last_move = concat('drop: ', name) where Games.id = id_game;
        delete from Uniformed_officers where Uniformed_officers.id_character = id_dropped;
        update Players set turn_time = now_time where Players.id = this_player_id;
        # my_char() - ОК! Ждет и выводит 3 полицейских
        commit;
        select 'Successful drop' as '';
    else 
        commit;
        select 'You cannot make a move' as Error;
    end if;
end;
alter procedure drop_card comment "(code varchar(10), user_name varchar(20), password varchar(10), name varchar(20)).
Процедура сбрасывает карту офицера в форме.";