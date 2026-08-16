from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime
from dremio_simple_query.connect import DremioConnection
from dremio_simple_query.connect import get_token
from os import getenv
import csv

#Делаем подключение
def get_dremio_client():
    
    ## Адрес API Dremio
    login_endpoint = "http://dremio:9047/apiv2/login"

    ## Логин/пароль для Basic Auth
    payload = {
        "userName": 'admin',
        "password": 'admin123'
    }

    ## Получаем токен
    token = get_token(uri = login_endpoint, payload=payload)

    ## Grps endpoint Dremio для быстрого взаимодействия
    arrow_endpoint="grpc://dremio:32010"

    ## Подключаемся
    dremio = DremioConnection(token, arrow_endpoint)    
    return dremio     

# Создаём таблицу
def create_table():
    
    dremio = get_dremio_client()
    df = dremio.toPandas("""
        CREATE TABLE IF NOT EXISTS catalog.orders (
            id BIGINT,
            order_number BIGINT,
            total NUMERIC(18,2),
            discount NUMERIC(18,2),
            buyer_id BIGINT
        ) PARTITION BY (order_number);""")

# Функция для чтения данных и генерации SQL-запросов
def generate_insert_queries():
    CSV_FILE_PATH = 'sample_files/sample.csv'
    with open( CSV_FILE_PATH, 'r') as csvfile:
        csvreader = csv.reader(csvfile)
    
        # Генерим запросы
        insert_queries = []
        is_header = True
        for row in csvreader:
            if is_header:
                is_header = False
                continue
            insert_query = f"INSERT INTO catalog.orders (id,order_number,total,discount,buyer_id) VALUES ({row[0]}, {row[1]}, {row[2]},{row[3]},{row[4]});"
            insert_queries.append(insert_query)
        
        # Сохраняем запросы
        with open('./dags/sql/insert_queries.sql', 'w') as f:
            for query in insert_queries:
                f.write(f"{query}\n")

#Отправляем данные в Dremio->Nessie->S3                               
def insert_data():  
    dremio = get_dremio_client()
    queries = []
    with open('./dags/sql/insert_queries.sql',mode='r') as file:
        queries = [line.rstrip() for line in file]
    for query in queries:
         dremio.toPandas(query)

#Определяем DAG
with DAG(
        dag_id="dremio_query_dag",
        start_date=datetime(2024, 12, 1),
        schedule_interval="@once", 
        catchup=False
    ) as dag:
    
        #Оператор для создания таблицы
        create_table = PythonOperator(
            task_id="run_dremio_create_table",
            python_callable=create_table
        )
        
        #Оператор для генерации запросов
        generate_queries = PythonOperator(
            task_id='generate_insert_queries',
            python_callable=generate_insert_queries
        )
        
        #Оператор для вставки данных
        run_insert_queries = PythonOperator(
            task_id="run_insert_queries",
            python_callable=insert_data
        )
        
        #Последовательность выполнения
        create_table>>generate_queries>>run_insert_queries