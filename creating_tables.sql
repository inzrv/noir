drop table if exists Secret_personalities;
drop table if exists Uniformed_officers;
drop table if exists Plainclothes_officers;
drop table if exists Active_personalities;
drop table if exists Thieves;
drop table if exists Policemen;
drop table if exists Cards_in_decks;
drop table if exists Characters;
drop table if exists Names;
drop table if exists Games;
drop table if exists Players;
drop table if exists Users;
drop table if exists Last_moves;

create table Users (name varchar(20) not NULL primary key, 
password varchar(10) not NULL);

create table Players (id int auto_increment primary key,
user_name varchar(20) not NULL, turn_time timestamp,
constraint foreign key(user_name) references Users(name) on delete cascade on update cascade);

create table Names (id int auto_increment primary key, name
varchar(20) unique not NULL);

create table Thieves (id int not NULL primary key,
status boolean not NULL default 1,
constraint foreign key(id) references Players(id) on delete cascade on update cascade);

create table Policemen (id int not NULL primary key,
constraint foreign key(id) references Players(id) on delete cascade on update cascade);

insert into Names (name) values
("Бренсон"), ("Владимир"), ("Джулиан"), ("Дружок"), ("Женева"),
("Закари"), ("Изольда"), ("Ирма"), ("Картрайт"), ("Клайв"), 
("Ксавье"), ("Куинтон"), ("Кэтрин"), ("Линнет"), ("Натан"), 
("Нейл"), ("Офелия"), ("Райан"), ("Тревор"), ("Фиби"), 
("Франклин"), ("Эвелин"), ("Элисс"), ("Эрвин"), ("Эштон");        

create table Games (id int auto_increment primary key, 
room_name varchar(10) not NULL, 
code varchar(10) unique not NULL, 
time_to_move time not NULL, 
id_creator int unique not NULL, 
id_connected int unique,
last_move varchar(20), 
constraint foreign key(id_creator) references Players(id) on delete cascade on update cascade,
constraint foreign key(id_connected) references Players(id) on delete set NULL on update cascade);

create table Characters (id int auto_increment primary key, r int not NULL, 
c int not NULL, token boolean not NULL default 1, 
id_game int not NULL, 
id_name int not NULL references Names(id) on delete restrict, 
unique(r, c, id_game), unique(id_game, id_name),
constraint foreign key(id_game) references Games(id) on delete cascade);

create table Plainclothes_officers (id_character int not NULL primary key, constraint foreign key(id_character) references Characters(id) on delete cascade);

create table Uniformed_officers (id_character int not NULL primary key, constraint foreign key(id_character) references Characters(id) on delete cascade);

create table Secret_personalities(id_character int not NULL primary key, constraint foreign key(id_character) references Characters(id) on delete cascade);

create table Active_personalities(id_character int not NULL primary key, constraint foreign key(id_character) references Characters(id) on delete cascade);

create table Cards_in_decks (id_character int not NULL primary key,  constraint foreign key(id_character) references Characters(id) on delete cascade);