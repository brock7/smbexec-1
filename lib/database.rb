#!/usr/bin/env ruby
# Single class to use any of the other database classes
class Driver
  attr_accessor :user, :pass, :host, :port, :database
  def initialize(db)
    yield self if block_given?
    pick_db(db)
  end

  def pick_db(db)
    case db
    when 'sqlite'
      SQLiteDatabase.new(@database)
    when 'postgres'
      PGDatabase.new(@database, @host, @port, @user, @pass)
    when 'mysql'
      MysqlDatabase.new(@database, @host, @user, @pass)
    else
      fail 'Options [sqlite postgres mysql]'
    end
  end
end

# Class for command SQL commands
class SQLCommands
  attr_accessor :table_name
  def create_database(dbname)
    execute("create database #{dbname}")
  end

  def drop_database(dbname)
    execute("drop database #{dbname}")
  end

  def create_table(table_name, table_columns =  {})
    @table_name = table_name
    columns = []
    table_columns.map do |column_name, type|
      columns << "#{column_name} #{type}"
    end
    execute("create table if not exists \
                 #{table_name} (#{columns.join(',')})")
  end

  def drop_table(table_name)
    execute("drop table #{table_name}")
  end

  def insert(values_hash = {})
    columns = []
    values = []
    values_hash.map do |column, value|
      columns << column.to_s && values << value
    end
    prepare(columns, values)
  end

  def prepare(columns, values)
    value_place_holder = (['?'] * values.size).join(',')
    insert = @con.prepare("insert into #{@table_name} (#{columns.join(',')}) \
                          values(#{value_place_holder})")
    insert.execute(*values)
  end
end

# Postgres specific needs
class PGDatabase < SQLCommands
  def initialize(database, host, port, username, password = nil)
    require 'pg'
    @con = PG::Connection.open(dbname: database, host: host,
                               port: port, user: username, password: password)
  rescue
    @con = PG::Connection.open(dbname: '', host: host,
                               port: port, user: username, password: password)
    create_database(database)
    @con = PG::Connection.open(dbname: database, host: host,
                               port: port, user: username, password: password)
  end

  def prepare(columns, values)
    value_place_holder = []
    values.each_with_index { |_, index| value_place_holder << "$#{index + 1}" }
    @con.prepare('insert', "insert into #{@table_name} (#{columns.join(',')}) \
                 values(#{value_place_holder.join(',')})")
    @con.exec_prepared('insert', [*values])
    execute('DEALLOCATE insert')
  end

  def execute(sql_command)
    @con.exec(sql_command)
  end

  def import(file_array)
    file_array.each do |file|
      execute("copy #{@table_name} from '#{file}' csv header")
    end
  end
end

# Sqlite specific needs
class SQLiteDatabase < SQLCommands
  def initialize(database)
    require 'sqlite3'
    @con = SQLite3::Database.new database
  end

  def execute(sql_command)
    @con.execute(sql_command)
  end
end

# MySQL specific needs
class MysqlDatabase < SQLCommands
  def initialize(database, host, username, password = nil)
    require 'mysql'
    @con = Mysql.new(hostname, username, password, database)
  end

  def execute(sql_command)
    @con.query(sql_command)
  end
end
