CREATE ROLE dify_user WITH LOGIN PASSWORD '<random_passwordで生成されるDBのパスワード>';
GRANT dify_user TO postgres;
CREATE DATABASE dify_db WITH OWNER dify_user;
\c dify_db
CREATE EXTENSION vector;
