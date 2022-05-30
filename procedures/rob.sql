# Убрал rob_close
# Исправил транзакцию: перенес проверки
# Добавил now_time

drop procedure if exists rob;
create procedure rob(code varchar(10), user_name varchar(20), password varchar(10), name varchar(20))
rob: begin

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

    #позиция жертвы
    declare victim_r int;
    declare victim_c int;

    #позиция вора
    declare thief_r int;
    declare thief_c int;

    # Текущее время. Будем получать его как можно ближе к вызову процедуры
    declare now_time timestamp default now(); 

    # Выносим проверки из транзакции

    #проверка имени и пароля
    if user_check(user_name, password) = false then
        select 'Wrong login or password!' as Error;
        leave rob;
    end if;
    
    #проверка кода комнаты
    if code_check(code) = false then
        select 'Wrong game code' as Error;
        leave rob;
    end if;

    set transaction isolation level READ COMMITTED;
    start transaction;

    # Получаем id игры и игроков, блокируем строки

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
        leave rob;
    end if;

    if opp_id is NULL then
        commit;
       select 'You cannot play alone' as Error;
       leave rob;
    end if;

    #проверка пользователя на вора
    if this_player_id not in (select id from Thieves) then
        commit;
        select 'You are not a thieve!' as Error;
        leave rob;
    end if;

    # user_del() - ОК! 
    # leave_game() - OK!
    # cur_state() - ОК! Ждет конца транзакции, выводит состояние после этого хода
    # shift() - ОК! Ждет конца тразакции.

    #проверяем количество офицеров в форме
    call q_check_t(id_game);
    
    #проверка жертвы
    #получаем ее координаты
    set victim_r = (select Characters.r from Characters 
        join Names on Names.id = Characters.id_name
        where Characters.id_game = id_game and Names.name = name);

    set victim_c = (select Characters.c from Characters 
        join Names on Names.id = Characters.id_name
        where Characters.id_game = id_game and Names.name = name);

    #получаем координаты активной личности в данной игре
    set thief_r = (select Characters.r from Characters join
        Active_personalities on Active_personalities.id_character = Characters.id
        where Characters.id_game = id_game);
    set thief_c = (select Characters.c from Characters join
        Active_personalities on Active_personalities.id_character = Characters.id
        where Characters.id_game = id_game);

    #если персонаж слишком далеко от нас, то мы не можем его обокрасть
    if (abs(thief_r - victim_r) > 1 or abs(thief_c - victim_c) > 1) then 
        commit;
        select 'You cannot steal a token from this character' as Error;
        leave rob;
    end if;

    # Проверка времени

    set time_to_move = (select Games.time_to_move from Games where Games.id = 
    id_game);
    set player_time = (select Players.turn_time from Players where Players.id = this_player_id);
    set opp_time = (select Players.turn_time from Players where Players.id = opp_id);

    # Ошибки с временем быть не может, т.к. строки Players заблокированы, поэтому
    # если во время выполнения этой транзакции начнется другая, то она будет ждать конца
    # текущей транзакции -> поменяет время только после апдейта Players

    # Запоминаем, чей ход был последним
    if (player_time > opp_time) then
        set last_move_time = player_time;
    else
        set last_move_time = opp_time;
    end if;

    if ((player_time = 0 and opp_time = 0) or
        (last_move_time = opp_time and can_move(last_move_time, time_to_move, now_time)) or
        (last_move_time = player_time and not can_move(last_move_time, time_to_move, now_time) 
        and timediff(now_time, last_move_time) > time_to_move))
    then
        #если перед этим ходом была не присяга и сброс карт
        if ((select last_move from Games where Games.id = id_game) in ('drop', 'oath')) then
            select 'Successful robbery after the oath!' as '';
        else
            select 'Successful robbery!' as '';
            update Players set turn_time = now_time where Players.id = this_player_id;
        end if;
        # Обновляем персонажей
        update Characters set token = false where 
            Characters.id_game = id_game and Characters.r = victim_r and Characters.c = victim_c;
        update Games set last_move = concat('robbery: ', name) where Games.id = id_game;
        commit;
    else 
        commit;
        select 'You cannot make a move' as Error;
        leave rob;
    end if;
    
    #проверяем количество жетонов на поле
    if (select count(*) from Characters where Characters.id_game = id_game and token = 1) = 0 
    then
        select 'You win!';
    end if;

end;
alter procedure rob comment "(code varchar(10), user_name varchar(20), password varchar(10), name varchar(20)). 
Процедура позволяет обокрасть персонажа с именем name.";
