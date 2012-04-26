require 'forwardable'

class ActiveRecord::Migration
  def self.alter_table(table_name, &block)
    alter_table_statement = case ActiveRecord::Base.connection.adapter_name.downcase
      when "mysql" then MySQLAlterTableStatement.new(table_name, self)
      else DefaultAlterTableStatement.new(table_name, self)
    end
    
    yield alter_table_statement
    alter_table_statement.execute
    alter_table_statement
  end
end

class ActiveRecord::Migration::DefaultAlterTableStatement
  extend Forwardable

  def initialize(table_name, base)
    @table_name = table_name
    @base = base
    @statements = []
  end
  
  def add_column(column_name, type, options = {})
    connection.add_column @table_name, column_name, type, options
  end

  def remove_column(column_name)
    connection.remove_column @table_name, column_name
  end
  
  def change_column(column_name, type, options = {})
    connection.change_column @table_name, column_name, type, options
  end

  def change_and_rename_column(column_name, new_column_name, type, options = {})
    connection.rename_column @table_name, column_name, new_column_name
    connection.change_column @table_name, new_column_name, type, options
  end

  def rename_column(column_name, new_column_name) #:nodoc:
    connection.rename_column @table_name, column_name, new_column_name
  end


  def add_index(column_name, options = {})
    connection.add_index @table_name, column_name, options
  end
  
  def remove_index(column_name, options = {})
    connection.remove_index @table_name, column_name, options
  end

  def execute
    # no-op
  end
  
  private
  
    def connection
      @base
    end
  
end


class ActiveRecord::Migration::MySQLAlterTableStatement
  extend Forwardable
  
  def_delegators :connection, 
    :quote_table_name, :quote_column_name, :type_to_sql, :add_column_options!, :index_name, :columns, :select_one
  
  def initialize(table_name, base)
    @table_name = table_name
    @base = base
    @statements = []
  end
  
  def add_column(column_name, type, options = {})
    sql = "ADD #{quote_column_name(column_name)} #{type_to_sql(type, options[:limit], options[:precision], options[:scale])}"
    add_column_options!(sql, options)
    @statements << sql
  end

  def remove_column(column_name)
    @statements <<"DROP #{quote_column_name(column_name)}"
  end
  
  def change_column(column_name, type, options = {})
    sql = "CHANGE #{quote_column_name(column_name)} #{quote_column_name(column_name)} #{type_to_sql(type, options[:limit], options[:precision], options[:scale])}"
    add_column_options!(sql, options)
    @statements << sql
  end

  def change_and_rename_column(column_name, new_column_name, type, options = {})
    sql = "CHANGE #{quote_column_name(column_name)} #{quote_column_name(new_column_name)} #{type_to_sql(type, options[:limit], options[:precision], options[:scale])}"
    add_column_options!(sql, options)
    @statements << sql
  end

  def rename_column(column_name, new_column_name) #:nodoc:
    options = {}
    if column = columns(@table_name).find { |c| c.name == column_name.to_s }
      options[:default] = column.default
      options[:null]    = column.null
    else
      raise ActiveRecord::ActiveRecordError, "No such column: #{@table_name}.#{column_name}"
    end
    current_type = select_one("SHOW COLUMNS FROM #{quote_table_name(@table_name)} LIKE '#{column_name}'")["Type"]
    sql = "CHANGE #{quote_column_name(column_name)} #{quote_column_name(new_column_name)} #{current_type}"
    add_column_options!(sql, options)
    @statements << sql
  end


  def add_index(column_name, options = {})
    column_names = Array(column_name)
    index_name   = options[:name] || index_name(@table_name, :column => column_names)
    index_type   = options[:unique] ? "UNIQUE" : ""

    quoted_column_names = column_names.map { |e| quote_column_name(e) }.join(", ")
    @statements << "ADD #{index_type} INDEX #{quote_column_name(index_name)} (#{quoted_column_names})".squish
  end
  
  def remove_index(column_name, options = {})
    index_name   = options[:name] || index_name(@table_name, [column_name])
    @statements << "DROP INDEX #{quote_column_name(index_name)}"
  end
  
  def to_s
    "ALTER TABLE #{quote_table_name(@table_name)} #{@statements.join(', ')}"
  end
  
  def execute
    @base.execute(self.to_s)
  end
  
  private
  
    def connection
      ActiveRecord::Base.connection
    end
  
end
