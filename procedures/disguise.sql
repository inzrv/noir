# Исправлена транзакция + now_time

drop procedure if exists disguise;
create procedure disguise (code varchar(10), user_name varchar(20), password varchar(10), name varchar(20))
disguise: begin

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

    #последний совершенный ход в данной игре
    declare last_move_time timestamp;

    # Текущее время. Будем получать его как можно ближе к вызову процедуры
    declare now_time timestamp default now(); 

    #проверка имени и пароля
    if user_check(user_name, password) = false then
        select 'Wrong login or password!' as Error;
        leave disguise;
    end if;
    
    #проверка кода комнаты
    if code_check(code) = false then
        select 'Wrong game code' as Error;
        leave disguise;
    end if;

    set transaction isolation level READ COMMITTED;
    start transaction;

    # leave_game() - ОК! Ждет конца транзакции, потом удаляет игрока
    # user_del() - ОК! 

    # Получаем id игры и игроков
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

    if this_player_id = 0 then
        commit;
        select 'You are not a member of this game' as Error;
        leave disguise;
    end if;
    
    #если пользователь один в игре
    if opp_id is NULL then
        commit;
        select 'You cannot play alone' as Error;
        leave disguise;
    end if;

    #проверка пользователя на вора
    if this_player_id not in (select id from Thieves) then
        commit;
        select 'You are not a thieve!' as Error;
        leave disguise;
    end if;

    # Если вызвать здесь my_char(), то она будет ждать конца тразакции, т.к мы заблокировали строки
    # После заврешения транзакции выдаст текущее состояние
    # cur_state() - ОК!

    # Проверка имени персонажа
    if name not in 
        (select * from 
            (select Names.name from Active_personalities 
                join Characters on Characters.id = Active_personalities.id_character
                join Names on Names.id = Characters.id_name
                join Games on Games.id = Characters.id_game
            union
            select Names.name from Secret_personalities 
                join Characters on Characters.id = Secret_personalities.id_character
                join Names on Names.id = Characters.id_name
                join Games on Games.id = Characters.id_game) 
        as AllChar)
    then
        commit;
        select 'You do not have a character with that name' as Error;
        leave disguise;
    end if;
     
    #проверяем количество офицеров в форме
    call q_check_t(id_game);

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

    if ((player_time = 0 and opp_time = 0) or 
        (last_move_time = opp_time and can_move(last_move_time, time_to_move, now_time)) or
        (last_move_time = player_time and not can_move(last_move_time, time_to_move, now_time) 
        and timediff(now_time, last_move_time) > time_to_move))
    then
        update Players set turn_time = now_time where Players.id = this_player_id;
        call disguise_close(this_player_id, name);
        update Games set last_move = 'disguise' where Games.id = id_game;
        commit;
        select 'Successful disguise!' as '';
        leave disguise;
    else
        commit;
        select 'You cannot make a move' as Error;
    end if;    
end;
alter procedure disguise comment "(code varchar(10), user_name varchar(20), password varchar(10), name varchar(20) - имя секретного персонажа). 
Процедура меняет активную личность на секретную с именем name.";





drop procedure if exists disguise_close;
create procedure disguise_close(id_player int, name varchar(20))
sql security invoker
disguise_close: begin

    #id персонажа текущей активной личности
    declare id_active int;
    #id персонажа, на которого хотим поменяться
    declare id_secret int; 
    
    set id_active = (select Characters.id from Active_personalities 
         join Characters on Characters.id = Active_personalities.id_character
         join Names on Names.id = Characters.id_name
         join Games on Games.id = Characters.id_game);

    if name in (select Names.name from Characters 
        join Names on Names.id = Characters.id_name where Characters.id = 
        id_active) 
    then 
        leave disguise_close;
    end if;

    set id_secret = (select Characters.id from Secret_personalities 
         join Characters on Characters.id = Secret_personalities.id_character
         join Names on Names.id = Characters.id_name
         where Names.name = name and Characters.id_game = id_game);

    update Active_personalities set id_character = id_secret where 
    id_character = id_active;
    update Secret_personalities set id_character = id_active where 
    id_character = id_secret;  
end;
alter procedure disguise_close comment "(id_player int, name varchar(20)). 
Процедура меняет активную личность на секретную и наоборот. Вызов происходит внутри процедуры disguise. Приватная.";