drop procedure if exists leave_game;
create procedure leave_game(code varchar(10), user_name varchar(20), password varchar(10)) 
comment "(code, user_name, password) Позволяет пользователю покинуть игру. 
Если уходит создатель, то игра удалаяется.";
leave_game: begin 
    #для хранения id игры 
    declare id_game int; 

    #для хранения id создателя
    declare id_creator int;

    #для хранения id подключившегося
    declare id_connected int;

    # Проверка имени и пароля 
    if user_check(user_name, password) = false then
        select 'Wrong login or password!' as Error; 
        leave leave_game; 
    end if; 

    set id_game = get_game_id(code); 
    set id_creator = (select Games.id_creator from Games where Games.id = id_game);
    set id_connected = (select Games.id_connected from Games where Games.id = id_game);

    set transaction isolation level READ COMMITTED;
    start transaction;

    delete from Players where Players.id = id_connected;

    if id_creator in (select Players.id from Players where Players.user_name = user_name) then
        delete from Players where Players.id = id_creator;
    end if;

    if row_count() = 0 then
        rollback;
        select 'You cannot leave this game' as Error; 
    leave leave_game;
    else
        commit;
        select concat('You left the room "', code, '"') as ''; 
    end if;
end;