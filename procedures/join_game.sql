# Исправлена транзакция

drop procedure if exists join_game;
create procedure join_game(code varchar(10), user_name varchar(20), password varchar(10))
join_game: begin

    #для хранения id подключившегося
    declare id_connected int;

    #для хранения id игры
    declare id_game int;
            
    #для хранения роли создателя
    declare creator_role int;
            
    #проверка имени и пароля
    if user_check(user_name, password) = false then
        commit;
        select 'Wrong login or password!' as Error;
        leave join_game;
    end if;
            
    #проверка кода комнаты
    if code_check(code) = false then
        commit;
        select 'Wrong game code' as Error;
        leave join_game;
    end if;

    set transaction isolation level READ COMMITTED;
    start transaction;

    set id_game = get_game_id(code);
    
    # Блокируем эту строку + проверяем на полноту
    if not exists(select * from Games where Games.id_connected is NULL and Games.id = id_game for update) then
        commit;
        select 'This game is full!' as Error; 
        leave join_game;
    end if;
            
    #если в комнате только создатель
    if (user_name = (select Players.user_name from Games join Players on Games.id_creator = Players.id
        where Games.id = id_game)) 
    then
        commit;
        select 'You cannot play with yourself!' as Error;
        leave join_game;
    end if;

    # Если пользователь удалиться к моменту добавления игрока, то транзакция откатывается
    # Добавляем нового игрока и запоминаем его id

    insert ignore into Players (user_name, turn_time) values (user_name, 0);
    if (row_count() = 0) then
        rollback;
        select 'Wrong login or password!' as Error;
        leave join_game;
    end if;
    set id_connected = (select Players.id from Players where Players.id = last_insert_id() lock in share mode);
            
    #изменяем строку в Games
    update Games set Games.id_connected = id_connected where Games.id = id_game;

    # user_del() работает нормально. Проверено
    # Если вызвать leave_game() от создателя, то все ОК! leave_game() ждет конца транзакции
    # Если вызвать leave_game() от подключившегося, то все ОК! 

    # Определяем роль подключившегося
            
    set creator_role = 
        (select R.role from 
            (select id, 1 as role from Thieves
                union
            select id, 2 as role from Policemen) as R 
                join Players on Players.id = R.id
                join Games on Games.id_creator = Players.id
                where Games.id = id_game);

    if creator_role = 1 then
        insert into Policemen (id) values (id_connected);
    else
        insert into Thieves (id) values (id_connected);
    end if;
    commit;
            
    select 'Successful connection to the game' as '';
            
    select room_name, code, time_to_move, Creators.user_name as creator_name, CreatorsR.role as creator_role, Connected.user_name as connected_name, ConnectedR.role as connected_role from Games 
        join Players as Creators on Games.id_creator = Creators.id
        join Players as Connected on Games.id_connected = Connected.id
        join (select id, 'Thieve' as role from Thieves
                union
            select id, 'Police' as role from Policemen) as CreatorsR on CreatorsR.id = Creators.id
        join (select id, 'Thieve' as role from Thieves
                union
            select id, 'Police' as role from Policemen) as ConnectedR on ConnectedR.id = Connected.id
            where Games.id = id_game;
end;
alter procedure join_game comment "(code varchar(10), user_name varchar(20), password varchar(10)). 
Процедура позволяет подключиться к игре с переданным кодом.";