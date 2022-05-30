drop procedure if exists cur_state;
create procedure cur_state(code varchar(10), user_name varchar(20), password varchar(10))
cur_state: begin
            
    #для хранения id игры
    declare id_game int;

    #id данного игрока
    declare this_player_id int;
            
    #для проверки статуса вора
    declare status_check boolean;
            
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

    #текущее время
    declare now_time timestamp default now(); 

    #проверка имени и пароля
    if user_check(user_name, password) = false then
        select 'Wrong login or password!' as Error;
        leave cur_state;
    end if;
            
    #проверка кода комнаты
    if code_check(code) = false then
        select 'Wrong game code' as Error;
        leave cur_state;
    end if;

    set id_game = get_game_id(code);

    set this_player_id = get_player_id(id_game, user_name);
    # Вероятно, лучше сразу проверить данного игрока, чтобы в случае удаления игры позже не выводить
    # лишнюю информацию
    if this_player_id = 0 then
        select 'You are not a member of this game' as Error;
        leave cur_state;
    end if;

    if (this_player_id in (select Games.id_creator from Games where Games.id = id_game)) then
        set opp_id = (select Games.id_connected from Games where Games.id = id_game);
    else 
        set opp_id = (select Games.id_creator from Games where Games.id = id_game);
    end if;

    select concat('Current state in the room "',code, '" ') as '';
            
    #проверяем, не победил ли полицейский
    if (select not status from (select id_creator as id from Games where Games.id = id_game
            union
        select id_connected from Games where Games.id = id_game) as AllP 
        join Thieves on Thieves.id = AllP.id
        and exists (select * from Games where Games.id = id_game)) 
    then
        select 'Cop won';
    end if;
            
    #проверяем, не победил ли вор
    if (select count(*) from Characters 
            where Characters.id_game = id_game and token != 0) < 1 and
        exists (select * from Games where Games.id = id_game)
    then
        select 'The thief won';
    end if;

    # Если пользователь один в игре
    if opp_id is NULL then
        select 'You do not have an opponent yet' as 'Whose turn?';
    else
        set time_to_move = (select Games.time_to_move from Games where Games.id = id_game);
        set player_time = (select Players.turn_time from Players where Players.id = this_player_id);
        set opp_time = (select Players.turn_time from Players where Players.id = opp_id);
            
        #запоминаем, чей ход был последним
        if (player_time > opp_time) then
            set last_move_time = player_time;
        else
            set last_move_time = opp_time;
        end if;
                
        if (player_time = 0 and opp_time = 0) then
            if (this_player_id in (select Thieves.id from Thieves)) then
                #если данный игрок вор, то он ходит первым
                select 'Your turn' as 'Whose turn?'; 
            else
                select 'Opponents turn' as 'Whose turn?';
            end if;
        else
            if ((last_move_time = opp_time and can_move(last_move_time, time_to_move, now_time)) or
                (last_move_time = player_time and not can_move(last_move_time, time_to_move, now_time) 
                and timediff(now_time, last_move_time) > time_to_move))
            then
                select 'Your turn' as 'Whose turn?'; 
                select time_left(last_move_time, time_to_move) as 'Time left';
            else
                select 'Opponents turn' as 'Whose turn?';
                select time_left(last_move_time, time_to_move) as 'Time left';
            end if; 
        end if;
    end if;

    # Офицеров в форме можно выводить без тразакции, т.к. если они поменяются до вывода поля,
    # то никакой ошибки в данных все равно не будет
    select Names.name as Uniformed_officers from Uniformed_officers
        join Characters on Uniformed_officers.id_character = Characters.id
        join Names on Names.id = Characters.id_name
        where Characters.id_game = id_game;
            
    set transaction isolation level REPEATABLE READ;
    start transaction;
    select Games.last_move as Last_move from Games where Games.id = id_game lock in share mode;
    call field(id_game);
    commit;
end;
alter procedure cur_state comment "(code varchar(10), user_name varchar(20), password varchar(10)). 
Процедура выводит текущее состояние игры с переданным кодом (положение карт на поле).";