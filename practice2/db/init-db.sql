CREATE TABLE users (
   id bigint,
   subscription_type varchar(128),
   m_revenue int,
   join_date varchar(20),
   last_payment varchar(20),
   country varchar(100),
   age int,
   gender varchar(6),
   device_type varchar(30),
   plan_duration varchar(30)
);

COPY users FROM '/home/users.csv' WITH (FORMAT csv, HEADER true);
