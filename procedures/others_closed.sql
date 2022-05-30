

drop procedure if exists new_player;
create procedure new_player(user_name varchar(20))
sql security invoker
new_player: begin
    insert into Players (user_name, turn_time) values (user_name, 0);
end;
alter procedure new_player comment "(user_name varchar(20) - имя пользователя). 
Процедура добавляет нового игрока при создании/подключении к игре. Приватная.";






drop function if exists user_check;
create function user_check(user_name varchar(20), password varchar(10)) returns boolean 
sql security invoker
begin
    return (user_name, password) in (select Users.name, Users.password from Users
        where Users.name = user_name lock in share mode);
    end;
alter function user_check comment "(user_name varchar(20) - имя пользователя, password varchar(10) - пароль пользователя). 
Функция возвращает true, если в БД существует пользователь с данными именем и паролем. Приватная";






drop function if exists code_check;
create function code_check(code varchar(10)) returns boolean
sql security invoker
begin
    if (select Games.code from Games where Games.code = code lock in share mode) is not NULL then
        return true;
    end if;
        return false;
    end;
alter function code_check comment "(code varchar(10)). Функция возвращает true, если в БД есть игра с данным кодом. Приватная";







drop function if exists get_game_id;
create function get_game_id(code varchar(10)) returns int
sql security invoker
begin
    declare id int default (select Games.id from Games where Games.code = code lock in share mode);
    return id;
    end;
alter function get_game_id comment "(code varchar(10)). Получает id игры по ее коду. Приватная.";




drop function if exists get_player_id;
create function get_player_id(id_game int, user_name varchar(20)) returns int
sql security invoker
get_player_id: begin

    #id данного игрока
    declare player_id int default 0;
            
    #если данный пользователь - создатель игры
    if user_name in 
        (select Players.user_name from Games join Players on
            Players.id = Games.id_creator where Games.id = id_game lock in share mode) 
    then 
        set player_id = 
        (select Games.id_creator from Games 
            join Players on Players.id = Games.id_creator
            where Games.id = id_game);
        return player_id;
        end if;


    if user_name in 
        (select Players.user_name from Games join Players on
            Players.id = Games.id_connected where Games.id = id_game lock in share mode) 
    then 
        set player_id = 
        (select Games.id_connected from Games join Players on
            Players.id = Games.id_connected where Games.id = id_game);
        return player_id;
    end if;
    return player_id;
    end;
alter function get_player_id comment "(id_game int, user_name varchar(20)). 
Процедура позволяет получить id игрока по имени пользователя и id игры. Приватная.";




drop procedure if exists field;
create procedure field (id_game int) 
sql security invoker
field: begin

    create temporary table Tmp_field (select  concat(name, ' ', token) as name, r, c from Characters 
        join Names on Names.id = Characters.id_name 
        where Characters.id_game = id_game 
        order by r, c);

    create temporary table C0 (select * from Tmp_field where c = 0);
    create temporary table C1 (select * from Tmp_field where c = 1);
    create temporary table C2 (select * from Tmp_field where c = 2);
    create temporary table C3 (select * from Tmp_field where c = 3);
    create temporary table C4 (select * from Tmp_field where c = 4);

    select C0.name, C1.name, C2.name, C3.name, C4.name from C0 
    join C1 using (r) 
    join C2 using (r)  
    join C3 using (r) 
    join C4 using (r);

    drop temporary table Tmp_field;
    drop temporary table  C0;
    drop temporary table  C1;
    drop temporary table  C2;
    drop temporary table  C3;
    drop temporary table  C4;
end;
alter procedure field comment "(id_game int). Вывод состояния игрового поля. Приватная.";





drop function if exists can_move;
create function can_move(last_move timestamp, time_to_move time, now_time timestamp) returns boolean
sql security invoker
can_move: begin
    declare delta long default (0);
    declare ttm_sec long default(time_to_sec(time_to_move));
    #считаем разницу, между сейчас и последним ходом
    set delta = time_to_sec(timediff(now_time, last_move));
    return ((delta div ttm_sec) % 2 = 0);
end;
alter function can_move comment "(last_move timestamp - время совершения последнего хода в игре, time_to_move time - время на ход в игре). 
Возвращает true, если вызывающий ее (через открытую процедуру хода) игрок может сделать ход.";







drop procedure if exists q_check_t;
create procedure q_check_t(id_game int)
sql security invoker
q_check_t: begin

    declare id_del int;

    # Все офицеры в форме из этой игры
    create temporary table Tmp_U (select * from Characters
        join Uniformed_officers on Uniformed_officers.id_character = Characters.id
        where Characters.id_game = id_game lock in share mode);

    if 2 < (select count(*) from Tmp_U) then
        set id_del = (select id from Tmp_U limit 1);
        delete from Uniformed_officers where Uniformed_officers.id_character = id_del;
    end if;
    drop temporary table Tmp_U;

end;
alter procedure q_check_t comment "(id_game). Проверяет количество офицеров в форме. Удаляет одного, если их больше 2. Вызов внутри хода вора. Приватная.";






drop function if exists q_check_c;
create function q_check_c(id_game int) returns boolean
sql security invoker
q_check_c: begin
    return 2 < (select count(*) from Characters
        join Uniformed_officers on Uniformed_officers.id_character = Characters.id
        where Characters.id_game = id_game lock in share mode);
end;
alter function q_check_c comment "(id_game). Проверяет количество офицеров в форме. true если их больше 2. Приватная.";






drop function if exists last_move_command;
create function last_move_command (id_game int) returns varchar(10)
last_move_command: begin
    declare last_move varchar(20) default (select Games.last_move from Games where Games.id = id_game lock in share mode);
    return substr(ltrim(last_move), 1, instr(last_move, ':')-1);
end;
alter function last_move_command comment "(id_game). Возвращает последнюю команду в игре без параметров";





drop function if exists time_left;
create function time_left(last_move timestamp, time_to_move time) returns time
sql security invoker
time_left: begin

    declare delta long default (0);

    #сколько времени прошло от начала хода (в секундах)
    declare time_passed long;

    declare ttm_sec long default(time_to_sec(time_to_move));
    #считаем разницу, между сейчас и последним ходом
    set delta = time_to_sec(timediff(now(), last_move));
    set time_passed = delta % ttm_sec;
    return sec_to_time(ttm_sec - time_passed);
end;
alter function time_left comment "(last_move timestamp, time_to_move time). Возвращает оставшееся на данный ход время. Приватная.";

