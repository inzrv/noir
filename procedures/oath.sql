drop procedure if exists oath;
create procedure oath(code varchar(10), user_name varchar(20), password varchar(10))
oath: begin

    #для хранения id игры
    declare id_game int;
    
    #для хранения id призываемого
    declare new_cop int;

    #для хранения нового имени нового полицейского
    declare new_cop_name varchar(20);
    
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
        commit;
        select 'Wrong login or password!' as Error;
        leave oath;
    end if;
    
    #проверка кода комнаты
    if code_check(code) = false then
        commit;
        select 'Wrong game code' as Error;
        leave oath;
    end if;

    set transaction isolation level READ COMMITTED;
    start transaction;
    
    # Получаем id игры и игроков

    set id_game = get_game_id(code);
    do (select count(*) from Games where Games.id = id_game for update);

    set this_player_id = get_player_id(id_game, user_name);
    do (select count(*) from Players where Players.id = this_player_id for update);

    if (this_player_id in (select Games.id_creator from Games where Games.id = id_game)) 
    then
        set opp_id = (select Games.id_connected from Games where Games.id = id_game);
    else 
        set opp_id = (select Games.id_creator from Games where Games.id = id_game);
    end if;
    do (select count(*) from Players where Players.id = opp_id for update);

    if this_player_id = 0 then
        commit;
        select 'You are not a member of this game' as Error;
        leave oath;
    end if;

    # Если вызвать здесь my_char(), то ждем окончания транзакции и выведем на экран 
    # 4 полицейских
    # Если вызвать, например, shift() от этого же игрока, то ждет конца тразакции
    # и пишет 'Drop the card first'. 
    # Если вызвать shift() от соперника, то ошибка: 'You cannot make a move', т.к мы не
    # сбросили карту и наше время не закончилось

    #если пользователь один в игре
    if opp_id is NULL then
        commit;
        select 'You cannot play alone' as Error;
        leave oath;
    end if;
    
    #проверяем количество офицеров
    if q_check_c(id_game) then
        commit;
        select 'Drop the card first' as Error;
        leave oath;
    end if;
    
    #проверка пользователя на полицейского
    if this_player_id not in (select id from Policemen) then
        commit;
        select 'You are not a cop!' as Error;
        leave oath;
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
    
    if (opp_time = 0 and player_time = 0) then
        commit;
        select 'You cannot make a move' as Error;
        leave oath;
    end if;
    
    if ((last_move_time = opp_time and can_move(last_move_time, time_to_move, now_time)) or
        (last_move_time = player_time and not can_move(last_move_time, time_to_move, now_time) 
        and timediff(now_time, last_move_time) > time_to_move))
    then
        # Если можем сделать ход, то обновляем данные
        # Так как поменять таблицу Cards_in_decks можно только с помощью
        # установленных процедур, то после блокировки таблиц Games и Players доступ к ним
        # будет только у этой транзакции, поэтому можно вызывать oath_close() тут
        set new_cop = (select oath_close(id_game));
        set new_cop_name = (select name from Characters join Names on Names.id = Characters.id_name
            where Characters.id = new_cop);
        update Games set last_move = concat('oath: ', new_cop_name) where Games.id = id_game;
        insert into Uniformed_officers values (new_cop);
        delete from Cards_in_decks where Cards_in_decks.id_character = new_cop;
        commit;
        select concat('New cop is: ', new_cop_name) as '';
    else 
        commit;
        select 'You cannot make a move' as Error;
    end if;
end;
alter procedure oath comment "(code varchar(10), user_name varchar(20), password varchar(10)). Призвать к присяге.";




drop function if exists oath_close;
create function oath_close(id_game int) returns int
sql security invoker
oath_close: begin
    return (select id_character from Cards_in_decks
        join Characters on Characters.id = Cards_in_decks.id_character
        join Names on Names.id = Characters.id_name
        where Characters.id_game = id_game
    order by rand() limit 1 lock in share mode);
end;
alter function oath_close comment "(id_game int). Возвращает случайную карту из колоды доказательсв";