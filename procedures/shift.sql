# Исправлена транзакция + now_time

drop procedure if exists shift;
create procedure shift(code varchar(10), user_name varchar(20), password varchar(10), x int, side varchar(5))
shift: begin

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

    #проверка номера столбца или строки
    if (x < 0 or x > 4) then
        select 'Wrong number of row or columns' as Error;
        leave shift;
    end if;
    
    #проверка направения сдвига
    if (side not in ('up', 'down', 'left', 'right')) then
        select 'Side set incorrectly' as Error;
        leave shift;
    end if;

    # Выносим эти проверки из транзакции

    #проверка имени и пароля
    if user_check(user_name, password) = false then
        select 'Wrong login or password!' as Error;
        leave shift;
    end if;
    
    #проверка кода комнаты
    if code_check(code) = false then
        commit;
        select 'Wrong game code' as Error;
        leave shift;
    end if;

    # Если удалить пользователя здесь, то выдаст ошибку 'You are not a member of this game',
    # т.к. удаление прошло раньше, чем проверка на нахождение в комнате
    # Если удалить оппонента-подключившегося, то выдаст ошибку 'You cannot play alone'.

    set transaction isolation level READ COMMITTED;
    start transaction;

    # Все после данной строки работает как раньше.
    # Изменен контроль времени: вместо now() теперь now_time
    # Получаем id игроков и игры, блокируем строки

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
        leave shift;
    end if;
    
    #если пользователь один в игре
    if opp_id is NULL then
        commit;
        select 'You cannot play alone' as Error;
        leave shift;
    end if;

    #проверяем количество офицеров в форме
    if (this_player_id in (select id from Thieves)) then
        #проверяем количество офицеров в форме
        call q_check_t(id_game);
    else
        if q_check_c(id_game) then
            commit;
            select 'Drop the card first' as Error;
            leave shift;
        end if;
    end if;
    
    #переходим к проверке времени

    set time_to_move = (select Games.time_to_move from Games where Games.id = id_game);
    set player_time = (select Players.turn_time from Players where Players.id = this_player_id);
    set opp_time = (select Players.turn_time from Players where Players.id = opp_id);

    #запоминаем, чей ход был последним
    if (player_time > opp_time) then
        set last_move_time = player_time;
    else
        set last_move_time = opp_time;
    end if;

    # Если два shifta вызываются одновременно (например здесь вызывается второй), то второй
    # ждет конца транзакции первого и разблокировки им строк, после этого выполняется.
    # Если здесь вызвать shift от этого же игрока, то все ОК! Пишет: 'You cannot make a move'.

    if (player_time = 0 and opp_time = 0) then
        if (this_player_id in (select Thieves.id from Thieves)) then
            #если данный игрок вор, то он ходит первым
            call shift_close(id_game, x, side);
            #обновляем время
            update Players set turn_time = now_time where Players.id = this_player_id;
            update Games set last_move = concat('shift', ': ', x, ' ', side) where Games.id = id_game;
            commit;
            select 'Successful shift!' as '';
            leave shift;
        else
            commit;
            select 'You cannot make the first move' as Error;
            leave shift;
        end if;
    else
        if ((last_move_time = opp_time and can_move(last_move_time, time_to_move, now_time)) or
            (last_move_time = player_time and not can_move(last_move_time, time_to_move, now_time) 
            and timediff(now_time, last_move_time) > time_to_move))
        then
            update Players set turn_time = now_time where Players.id = this_player_id;
            call shift_close(id_game, x, side);
            update Games set last_move = concat('shift', ': ', x, ' ', side) where Games.id = id_game;
            commit;
            select 'Successful shift!' as '';
            leave shift;
         else
            commit;
            select 'You cannot make a move' as Error;
            leave shift;
        end if; 
    end if;
end;
alter procedure shift comment "(code varchar(10), user_name varchar(20), password varchar(10), x int, side varchar(5)). 
Ход пользователя user_name в игре с кодом code. 
Сдвигает строку или столбец с номером x (от 0 до 4) в направлении side (up, down, left, right).";







drop procedure if exists shift_close;
create procedure shift_close(id_game int, x int, side varchar(5))
sql security invoker
shift_close: begin

    case side
    when 'right' then
        update Characters set c = -1 where Characters.id_game = id_game and r = x and c = 0;
        update Characters set c = (c + 1) % 5 
            where Characters.id_game = id_game and r = x and c != -1
            order by c desc;
        update Characters set c = 1 where Characters.id_game = id_game and c = -1;
        leave shift_close;
    when 'left' then
        update Characters set c = -1 where Characters.id_game = id_game and r = x and c = 4;
        update Characters set c = (c + 4) % 5 
            where Characters.id_game = id_game and r = x and c != -1
            order by c;
        update Characters set c = 3 where Characters.id_game = id_game and c = -1;
        leave shift_close;
    when 'up' then
        update Characters set r = -1 where Characters.id_game = id_game and c = x and r = 4;
        update Characters set r = (r + 4) % 5 
            where Characters.id_game = id_game and c = x and r != -1
            order by r;
        update Characters set r = 3 where Characters.id_game = id_game and r= -1;
        leave shift_close;
    else
        update Characters set r = -1 where Characters.id_game = id_game and c = x and r = 0;
        update Characters set r = (r + 1) % 5 
            where Characters.id_game = id_game and c = x and r != -1
            order by r desc;
        update Characters set r = 1 where Characters.id_game = id_game and r = -1;
        leave shift_close;
    end case;
end;
alter procedure shift_close comment "(id_game int, x int, side varchar(5)). 
Процедура сдвигает столбец или строку с номером x в направлении side. Вызов происходит внутри процедуры shift. Приватная.";