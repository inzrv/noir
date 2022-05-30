drop procedure if exists user_reg;
create procedure user_reg(user_name varchar(20), password varchar(10))
user_reg: begin

 # Здесь транзакции не нужны, просто проверяем количество обновленных строк

    if length(user_name) < 4 then 
        select 'Username must be at least four letters long' as Error;
        leave user_reg;
    end if;
    insert ignore into Users values (user_name, password);  
    if (select row_count()) = 0 then 
        select concat ('Name "', user_name, '" is already taken') as Error;
        leave user_reg;
    end if;
    select concat('User ', user_name, ' - ', password,  ' successfully registered') as 'Success!';
end;
alter procedure user_reg comment "(user_name varchar(20) - имя пользователя, 
password varchar(20) - пароль пользователя). Процедура регистрирует нового пользователя";



drop procedure if exists user_del;
create procedure user_del(user_name varchar(20), password varchar(10))
user_del: begin
    delete from Users where name = user_name and Users.password = password;
    if (select row_count()) then
        select 'User deleted successfully' as 'Success!';
    else
        select 'Wrong login or password!' as Error;
    end if;
end;
alter procedure user_del comment "((user_name varchar(20), password varchar(10)). Удаляет пользователя и все игры, где он создатель.";