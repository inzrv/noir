# Исправлена транзакция

drop procedure if exists fold;
create procedure fold(code varchar(10), user_name varchar(20), password varchar(10))
fold: begin
    #для хранения id игры
    declare id_game int;

    #id данного игрока
    declare this_player_id int;

    #проверка имени и пароля
    if user_check(user_name, password) = false then
        select 'Wrong login or password!' as Error;
        leave fold;
    end if;
    
    #проверка кода комнаты
    if code_check(code) = false then
        select 'Wrong game code' as Error;
        leave fold;
    end if;

    # Выносим временную таблицу
    create temporary table F(name varchar(20));

    set id_game = get_game_id(code);
    set this_player_id = get_player_id(id_game, user_name);

    if this_player_id = 0 then
        select 'You are not a member of this game' as Error;
        leave fold;
    end if;

    set transaction isolation level READ COMMITTED;
    start transaction read only;

    insert into F 
    (select name from Characters 
        join Names on Names.id = Characters.id_name
        where Characters.id_game = id_game and
            Characters.id not in (select Cards_in_decks.id_character from Cards_in_decks)
            and Characters.id not in(select Active_personalities.id_character from Active_personalities)
            and Characters.id not in(select Secret_personalities.id_character from Secret_personalities)
            and Characters.id not in(select Plainclothes_officers.id_character from Plainclothes_officers)
            and Characters.id not in(select Uniformed_officers.id_character from Uniformed_officers)
    );

    if row_count() = 0 then
        commit; 
        drop temporary table F;
        select 'Empty'  as 'Discarded cards';
        leave fold;
    else
        commit;
        select name as 'Discarded cards' from F;
        drop temporary table F;
    end if;
end;
alter procedure fold comment "(code varchar(10), user_name varchar(20), password varchar(10)). 
Процедура позволяет увидеть карты, сброшенные полицейским после призыва к присяге.";