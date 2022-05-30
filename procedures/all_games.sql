drop procedure if exists all_games;
create procedure all_games()
all_games: begin 
    select 'All games:' as '';
    set transaction isolation level READ COMMITTED;
    start transaction read only;
    if exists (select * from Games lock in share mode) then 
        select room_name, time_to_move, Creators.user_name as creator_name, CreatorsR.role as creator_role,
        Connected.user_name as connected_name, ConnectedR.role as connected_role from Games
            join Players as Creators on Creators.id = Games.id_creator
            left join Players as Connected on Connected.id = Games.id_connected
            join (select id, 'Thieve' as role from Thieves
                    union
                select id, 'Police' as role from Policemen) as CreatorsR on CreatorsR.id = Creators.id
            left join (select id, 'Thieve' as role from Thieves
                        union
                    select id, 'Police' as role from Policemen) as ConnectedR on ConnectedR.id = Connected.id;
    end if;
    commit;
end;
alter procedure all_games comment "(). Возвращает список всех игр с игроками и ролями.";


# Есть несколько подходов: 
#  1) Можно обойтись без блокировок и тразакций и выводить максимально актуальную
# информацию, но тогда будет выводиться пустая строка, если успели удалить игры после проверки

# 2) Можно блокировать строки на время тразакции, тогда игры нельзя удалить, если сейчас выполняется 
# транзакция, но из нее можно выйти подключившемуся или удалить его пользователя