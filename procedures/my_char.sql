# Проверки вынесены из транзакции

drop procedure if exists my_char;
create procedure my_char(code varchar(10), user_name varchar(20), password varchar(10))
my_char: begin

    #id данного игрока
    declare this_player_id int;

    #id данной игры
    declare id_game int;

    #проверка имени и пароля
    if user_check(user_name, password) = false then
        select 'Wrong login or password!' as Error;
        leave my_char;
    end if;
    
    #проверка кода комнаты
    if code_check(code) = false then
        select 'Wrong game code' as Error;
        leave my_char;
    end if;

    # Получаем id игрока и игры

    set id_game = get_game_id(code);
    set this_player_id = get_player_id(id_game, user_name);

    if this_player_id = 0 then
        commit;
        select 'You are not a member of this game' as Error;
        leave my_char;
    end if;

    call host700505_sandbox.tormoz(9);

    set transaction isolation level REPEATABLE READ;
    start transaction read only;

    if this_player_id in (select id from Thieves) then
        select name, role from 
            (select *, 'Active' as role  from Active_personalities 
                union
            select *, 'Secret' as role from Secret_personalities) as Thvs
            join Characters on Thvs.id_character = Characters.id
            join Names on Names.id = Characters.id_name
            where Characters.id_game = id_game;
        commit;
        leave my_char;
    end if;

    if this_player_id in (select id from Policemen) then
        select name, role from 
            (select *, 'Plainclothes' as role from Plainclothes_officers 
                union
            select *, 'Uniformed' as role from Uniformed_officers) as Cops
            join Characters on Cops.id_character = Characters.id
            join Names on Names.id = Characters.id_name
            where Characters.id_game = id_game;
        commit;
        leave my_char;
    end if;

    select 'You are not a member of this game' as Error;
end;
alter procedure my_char comment "(code varchar(10), user_name varchar(20), password varchar(10)). 
Процедура выводит имена персонажей и их роли в игре с кодом code у пользователя с именем user_name.";