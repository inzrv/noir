# Исправлена транзакция
# Вынесено создание и удаление временной таблицы

drop procedure if exists new_game;
create procedure new_game(room_name varchar(10), code varchar(10), time_to_move time, user_name varchar(20), password varchar(10), role int)
new_game: begin
            
    #для хранения id создателя
    declare id_creator int;
            
    #для хранения id игры
    declare id_game int;

    # Выносим эти проверки за транзакцию

    # Проверка имени и пароля
    if user_check(user_name, password) = false then
        select 'Wrong login or password!' as Error;
        leave new_game;
    end if;

     # Проверка кода комнаты
    if code_check(code) then
        select concat('Code "', code, '" is already taken') as Error;
        leave new_game;
    end if;

    # Вынесем создание временной таблицы
    create temporary table Tmp_n(r int, c int);
    insert into Tmp_n values
        (0,0), (0,1), (0,2), (0,3), (0,4),
        (1,0), (1,1), (1,2), (1,3), (1,4),
        (2,0), (2,1), (2,2), (2,3), (2,4),
        (3,0), (3,1), (3,2), (3,3), (3,4),
        (4,0), (4,1), (4,2), (4,3), (4,4);


    set transaction isolation level READ COMMITTED;
    start transaction;

    # Добавляем игрока. INSERT заблокирует его строку для измений пока данная транзакция не закончиться
    # Если к этому моменту данного пользователя нет, то row_count() = 0 и мы заврешаем транзакцию

    insert ignore into Players (user_name, turn_time) values (user_name, 0);
    if (row_count() = 0) then
        commit;
        select 'Wrong login or password!' as Error;
        drop temporary table Tmp_n;
        leave new_game;
    end if;

    set id_creator = (select Players.id from Players where Players.id = last_insert_id() lock in share mode);

    # На данном этапе есть все данные для создания записи в таблице Games. Добавляем запись и запоминаем id
    # Так как на RC возможно неповторяемое чтение, то мы проверяем, не добавилась ли игра
    # с таким же кодом. Если игру с таким кодом успели добавить между проверкой и строкой ниже, то откатываемся

    insert ignore into Games (room_name, code, time_to_move, id_creator, last_move) 
        values (room_name, code, time_to_move, id_creator, NULL);
            
    if (select row_count() = 0) then
        rollback;
        select concat('Code "', code, '" is already taken') as Error;
        drop temporary table Tmp_n;
        leave new_game;
    end if;

    # Успешно добавили игру и заблокировали ее строку, теперь получаем ее id 
    set id_game = (select Games.id from Games where Games.id = last_insert_id());

    # Удалить пользователя через user_del() можно и после создания игры.
    # Все работает корректно, протестировано
    # После создания игры из нее можно выйти через leave_game() 
    # Все работает корректно, leave_game ждет завершения текущей тразакции и затем удаляет
    # данную игру

    # Удалить или изменить данную строку теперь нельзя до конца транзакции

    # Добавляем 25 новых персонажей в таблицу Characters
    insert into Characters (r,c, token, id_game, id_name) select r,c,1 as token, id_game, Names.id from Tmp_n join Names
        where r * 5 + c + 1 = id;
            
    # Далее до конца транзакции 25 новых строк не будут доступны для удаления или изменения
            
    create temporary table Random6 
    #получаем 6 случайных персонажей данной игры
    select Characters.id from Characters 
        join Names on Names.id = Characters.id_name
        join (select * from Names order by rand() limit 6) as Tmp1 on Tmp1.id = Names.id
        where Characters.id_game = id_game; 
            
    #выделяем 6 персонажей под личности вора и полицейского
            
    #добавляем личности вора
    insert into Active_personalities select * from Random6 order by id limit 1;
    insert into Secret_personalities select * from Random6 order by id limit 2 offset 1;
            
    #добавляем личности полицейского
    insert into Plainclothes_officers select * from Random6 order by id limit 1 offset 3;
    insert into Uniformed_officers select * from Random6 order by id limit 2 offset 4;

    #добавляем 19 персонажей в колоду доказательств
            
    insert into Cards_in_decks select Characters.id from Characters 
        where Characters.id_game = id_game and Characters.id not in (select * from Random6);

    # Аналогично, редактированные выше таблицы не могут быть изменены извне
            
    drop temporary table Random6;
            
    # Если пользователь не знает за кого играть
    if role = 0 then
        set role = floor(rand(1)*2+1);
    end if;
            
    # Так как id_creator все еще существует (в силу того, что INSERT установил блокировку на Players.id_creator),
    # то мы можем добавить его в вора или полицейского

    # Если создатель - вор
    if role = 1 then
        insert into Thieves (id) values (id_creator);

    # Если создатель - полицейский
    else
        insert into Policemen (id) values (id_creator);
    end if;

    commit;

    drop temporary table Tmp_n;
    select 'Game successfully created' as '';

    select room_name, code, time_to_move, user_name as creator_name, R.role as creator_role from 
        (select id, 'Thieve' as role from Thieves
            union
        select id, 'Police' as role from Policemen) as R 
        join Players on Players.id = R.id
        join Games on Games.id_creator = Players.id
        where Games.id = id_game;
end;
alter procedure new_game comment "(room_name varchar(10), code varchar(10), time_to_move time, user_name varchar(20), password varchar(10), role int). 
Процедура создает игру с преданными параметрами. Создатель может выбрать роль (0 - любая, 1 - вор, иначе - полицейский).";