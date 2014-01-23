require 'parallel'
require "#{BASE}/libs/page_utils"
require "#{BASE}/libs/database"

class ExecutionContext
	def initialize(stored_data)
		@queries = []

		@default_allowed = ['[]']
		@allowed = @default_allowed

		@stored_data = stored_data

		@connections = {}
	end

	def ds
		self
	end

	def verify_validity(call)
		raise NotAllowedError.new("#{call} not allowed.") if !@allowed.include?(call)
	end

	def [](datasource_name)
		verify_validity('[]')

		@datasource_name = datasource_name
		@allowed = ['query']

		return self
	end

	def query(query, *params)
		verify_validity('query')

		@queries << {datasource_name: @datasource_name, query: query, params: params}
		@allowed = ['[]', 'query', 'display']

		return self
	end

	def user_variables(key)
		@stored_data[:user_variables][key]
	end

	def get_datasource_connection(datasource_name=nil)
		datasource_name = datasource_name || @datasource_name

		if @connections[datasource_name] == nil
			datasource_info = get_conf['datasources'][datasource_name]
			raise DatasourceNotFoundError.new(datasource_name) if datasource_info == nil

			@connections[datasource_name] = connect(datasource_info, nil)
		end

		return @connections[datasource_name]
	end

	def request_param(key)
		return @stored_data[:request_params][key][:value] if @stored_data[:request_params].has_key?(key)
		raise RequestParamNotFound.new(key)
	end

	def request_param?(key)
		@stored_data[:request_params].has_key?(key)
	end

	def display(type, options={})
		verify_validity('display')

		results = Parallel.map(@queries, :in_processes => 10) {|query_info|
			connection = get_datasource_connection(query_info[:datasource_name])
			connection.query_table(query_info[:query], *query_info[:params])
		}

		cols = results[0][0]

		displayable_data = results.collect {|cols, result| result }.inject(:+)

		@allowed = ['query', '[]']

		if type == :table
			render_table(cols, displayable_data)
		elsif type == :scalar
			displayable_data[0][0].to_s
		else
			emit_chart(type, displayable_data, cols, nil, options['title'], options['xtitle'], options['ytitle'], options['height'], options['width'])
		end
	end

	def _binding
		binding
	end
end

class NotAllowedError < Exception
	attr_reader :message

	def initialize(message)
		@message = message
	end
end

class UntypedRequestParamError < Exception
	attr_reader :message

	def initialize(key)
		@message = "Cannot return the value of an untyped form paramter."
	end
end

class DatasourceNotFoundError < Exception
	attr_reader :message

	def initialize(datasource_name)
		@message = "Datasource #{datasource_name} configuration not found."
	end
end

class RequestParamNotFound < Exception
	attr_reader :message

	def initialize(param_name)
		@message = "Request parameter #{param_name} not found."
	end
end
