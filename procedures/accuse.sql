# Исправлена транзакция, добавлено now_time


drop procedure if exists accuse;
create procedure accuse (code varchar(10), user_name varchar(20), password varchar(10), name varchar(20))
accuse: begin
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

    #позиция обвиняемого
    declare accused_r int;
    declare accused_c int;

    #позиция офицера в штатском
    declare plain_r int;
    declare plain_c int;
    
    #позиция офицера в форме 1
    declare u1_r int;
    declare u1_c int;
    
    #позиция офицера в форме 2
    declare u2_r int;
    declare u2_c int;

    # Текущее время. Будем получать его как можно ближе к вызову процедуры
    declare now_time timestamp default now(); 

    #проверка имени и пароля
    if user_check(user_name, password) = false then
        select 'Wrong login or password!' as Error;
        leave accuse;
    end if;
    
    #проверка кода комнаты
    if code_check(code) = false then
        select 'Wrong game code' as Error;
        leave accuse;
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
        leave accuse;
    end if;
    
    # Проверяем количество офицеров
    if q_check_c(id_game) then
        commit;
        select 'Drop the card first' as Error;
        leave accuse;
    end if;
    
    # Если пользователь один в игре
    if opp_id is NULL then
        commit;
        select 'You cannot play alone' as Error;
        leave accuse;
    end if;

    # Проверка пользователя на полицейского
    if this_player_id not in (select id from Policemen) then
        commit;
        select 'You are not a cop!' as Error;
        leave accuse;
    end if;
    
    # rob() - ОК! Ждет завершения и запускается
    # cur_state() - ОК!

    #получаем координаты обвиняемого
    create temporary table Accured_Pos(select Characters.r, Characters.c from Characters 
        join Names on Names.id = Characters.id_name
        where Characters.id_game = id_game and Names.name = name);
    set accused_r = (select r from Accured_Pos); 
    set accused_c = (select c from Accured_Pos);
    drop temporary table Accured_Pos;
    
    #получаем координаты полицейского в штатском
    create temporary table Plain_Pos(select Characters.r, Characters.c from Characters 
        join Plainclothes_officers on Plainclothes_officers.id_character = Characters.id
        where Characters.id_game = id_game);
    set plain_r = (select r from Plain_Pos);
    set plain_c = (select c from Plain_Pos);
    drop temporary table Plain_Pos;
    
    #получаем координаты офицеров в форме
    create temporary table Uni_Pos(select Characters.r, Characters.c from Characters 
        join Uniformed_officers on Uniformed_officers.id_character = Characters.id
        where Characters.id_game = id_game);
    set u1_r = (select r from Uni_Pos order by r,c limit 1);
    set u1_c = (select c from Uni_Pos order by r,c limit 1);
    set u2_r = (select r from Uni_Pos order by r,c limit 1 offset 1);
    set u2_c = (select c from Uni_Pos order by r,c limit 1 offset 1);
    drop temporary table Uni_Pos;
    
    #проерка соседства с обвиняемым
    if (abs(accused_r - plain_r) > 1 or abs(accused_c - plain_c) > 1) and
       (abs(accused_r - u1_r) > 1 or abs(accused_c - u1_c) > 1) and 
       (abs(accused_r - u2_r) > 1 or abs(accused_c - u2_c) > 1) then 
            commit;
            select 'You cannot blame this character' as Error;
            leave accuse;
    end if;
    
    #обвиняемый находится рядом с полицейским
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
        leave accuse;
    end if;

    if ((last_move_time = opp_time and can_move(last_move_time, time_to_move, now_time)) or
        (last_move_time = player_time and not can_move(last_move_time, time_to_move, now_time) 
        and timediff(now_time, last_move_time) > time_to_move))
    then
        #если можем сделать ход, то обновляем информацию
        update Players set turn_time = now_time where Players.id = this_player_id;
        update Games set last_move = concat('accuse: ', name) where Games.id = id_game;
        if accuse_close(id_game, accused_r, accused_c) then
            update Thieves set status = 0 where Thieves.id = opp_id; 
            commit;
            select 'You caught the thief' as '';
            leave accuse;
        else
            commit;
            select 'You blamed the innocent' as '';
        end if;
    else
        commit;
        select 'You cannot make a move' as Error;
    end if;
end;
alter procedure accuse comment "(code varchar(10), user_name varchar(20), password varchar(10), name varchar(20)). 
Процедура позволяет обвинить персонажа с именем name.";




drop function if exists accuse_close;
create function accuse_close(id_game int, r int, c int) returns boolean
sql security invoker
accuse_close: begin
    return (r = (select Characters.r from Characters 
        join Active_personalities on Active_personalities.id_character = Characters.id
        where Characters.id_game = id_game) 
        and
        c = (select Characters.c from Characters 
        join Active_personalities on Active_personalities.id_character = Characters.id
        where Characters.id_game = id_game));
end;
alter function accuse_close comment "(id_game int, r int, c int). 
Возвращает true, если активная личность вора находится на месте [r,c]. Приватная";