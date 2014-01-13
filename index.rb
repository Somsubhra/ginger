require 'json'
require 'uri'

require './libs/params'
require './config'

require './libs/page_utils'
require './libs/database'
require './libs/stop_evaluation'
require './libs/ginger_parser'
require './libs/HTMLGenerator.rb'
require './libs/CSVGenerator.rb'
require './libs/common_utils.rb'

require 'rubygems'
require 'sinatra'
require 'redcloth'

base_files_directory = get_conf['base_files_directory']

def template_to_html(content, params)
	convertors = []

	convertors = [
		proc {|content| parse_ginger_doc(content) },
		proc {|content| HTMLGenerator.new(params).generate(content) },
		proc {|content|
			redcloth = RedCloth.new(content)
			redcloth.extend FormTag
			redcloth.to_html(content)
		}
	]

	new_content = content

	convertors.each {|convertor|
		new_content = convertor.call(new_content)
	}

	return new_content
end

def parse_param_data(template_params)
	name = strip_quotes(template_params['name'].to_s)
	title = strip_quotes(template_params['title'].to_s)
	type = strip_quotes(template_params['type'].to_s)

	return name, title, type
end

def store_param_data(stored_data, template_params, params, name, title, type)
	param_name = "p_#{name}"

	if params.has_key?(param_name) && params[param_name].length > 0
		stored_data[:request_params][name] = {:value => params[param_name], :type => type}
	else
		if (template_params['required'].to_s || "").downcase == 'true'
			raise StopEvaluation.new(title)
		end
	end
end

def add_cache_request(url)
	return if url.index('cache=true') != nil
	return url + '&cache=true' if url.index('?') != nil
	return url + '?cache=true'
end

def remove_cache_request(url, cache_switch)
	return "" if url == nil
	clean_url = url.gsub(/&cache=#{cache_switch}/, "")
	clean_url = clean_url.gsub(/\?cache=#{cache_switch}/, "")
	clean_url = clean_url.gsub(/cache=#{cache_switch}/, "") if clean_url.index("cache=#{cache_switch}") == 0
	clean_url = clean_url.gsub(/\?\s*$/, "")

	return clean_url
end

get '/' do
	@list_of_pages = list_of_pages
	haml :page_list
end

get '/explore/:datasource' do
	template = "[:#{params['datasource']} show tables; :]"

	@page = {}
	@page['content'] = template_to_html(template, params)

	haml :show_page
end

get '/explore/:datasource/:table' do
	template = "[:#{params['datasource']} desc #{params['table']}; :]"

	@page = {}
	@page['content'] = template_to_html(template, params)

	haml :show_page
end

get '/page/:page_id/edit' do
	@page_id = params[:page_id]
	@page = nil

	@page_title = "Edit page"

	if page_exists(@page_id)
		@page = load_page(@page_id)
	end

	haml :edit_page
end

get '/page/:page_id' do
	stored_data = {
		:request_params => {
		},
		:user_variables => {
		}
	}

	@page_id = params[:page_id]

	if page_exists(@page_id)
		@page = load_page(@page_id)

		uri = URI.parse(request.url)

		query_params = remove_cache_request(uri.query, true) || ""
		last_modified_time, cached_page = get_cached_page(@page_id, query_params)

		if params['id']
			parse_tree = parse_ginger_doc(@page['content'])
			content_type 'text/plain'

			return CSVGenerator.new(params).generate(parse_tree)
		elsif (params['cache'] != 'true' && cached_page)
			@page['content'] = cached_page
			cached_time = Time.now - last_modified_time

			minute = 60
			hour = 60 * minute
			day = 24 * hour

			if cached_time / minute < 2
				@cached_time = "#{cached_time.round} seconds"
			elsif cached_time / hour < 2
				@cached_time = "#{(cached_time / minute).round} minutes"
			elsif cached_time / day < 2
				@cached_timecached_time = "#{(cached_time / hour).round} hours"
			else
				@cached_timecached_time = "#{(cached_time / day).round} days"
			end

			@cached_time = "This page was cached #{@cached_time} ago."
		else
			begin
				@page['content'] = template_to_html(@page['content'], params)

				if params['cache'] == 'true'
					write_cached_page(@page_id, query_params, @page['content'])
					return redirect to(remove_cache_request(request.url, true)) 
				end
			rescue StopEvaluation => e
				@page['content'] = e.message
			end
		end

		haml :show_page
	else
		@page_title = "New page"
		@page = {}
		haml :edit_page
	end
end

post '/page/:page_id' do
	if params['delete_page'] == 'true'
		delete_page(params[:page_id])
		return redirect to("/")
	end

	if params['destroy_cache'] == 'true'
		destroy_cache(params[:page_id])
		return redirect to(request.url)
	end

	content = {
		'title' => params[:title],
		'content' => params[:content]
	}

	page_id = params[:page_id]

	write_page(page_id, content)

	redirect to("/page/#{page_id}")
end

get '/help' do
	help_text = <<-END
h2. Variables

<pre>
<:var:>
Displays the value of var.
</pre>

h2. Case

<pre>
<: var=b :>

<:case:var:var2 (options=a,b,c values=1,2,3)
When var is a, var2 is set to 1; when var is b, var2 is set to 2, etc. The name var can may refer to either a variable or a form parameter. If a variable and a form parameter exist by the same name, the variable is given preference.

<:var2:>
Display the value of var2, which would be 2

</pre>

h2. Tabular data

<pre>
[:peopledata select * from people :]
peopledata is the data source being queried. The query "select * from people" is executed against this data source, and the result is displayed in tabular format. Tabular format is the default when the result is multiple rows or columns.

[:peopledata select count(*) from people :]
Since the result has a single row and column, it will be displayed as plain text without any table markup.

To explicitly specify the format:
[:peopledata:scalar select count(*) from people :]

OR

[:peopledata:table select count(*) from people :]

[:peopledata select * from people {: where city='::city::' :}]
The where clause will be added only if the city variable exists.
The value of city will be escaped.

The where clauses will be added if city exists.
[:peopledata select * from people {:city? where 1=2 :}]

To specify a datasource that is contained in a variable:
<:dsname=employee_ds:>
[:{:dsname:} select * from people :]

This is useful when the data source needs to be changed based on some user specified input. A case statement may be used to set a variable based on the value of the input, and that variable may be used as a data source.

</pre>

h2. Graphs

<pre>
[:peopledata:pie select city, count(*) from people group by city :]
The result set would look something like this:
Mumbai, 10
Delhi, 20
Bangalore, 30
In each row, the first column contains the title, and the second column contains corresponding value.

[:peopledata:bar (xtitle='Some title' ytitle='Some other title') select city, count(*) from people group by city :]
Bar and line charts are similar. xtitle and ytitle parameters may be specified.
</pre>

h2. Forms

<pre>
Forms allow the viewer of the page to supply values with which queries on the page may be parameterized.

Forms are ideally declared at the top of the page. They must use the following syntax:
form. <:input:dropdown (name=country options=US,India,China values=us,india,cn title=Country) :> <:input:submit:>

A form declaration must be on a single line. The submit button at the end of the form declaration is at this time essential.

Here are the currently supported form fields:

DROPDOWN

<:input:dropdown (name=country options=US,India,China values=us,india,cn title=Country) :>
A dropdown will b displayed showing the options US, India, China, with corresponding values us, india and cn. When supplied by the user, they will be available in a variable named "country". The title of the dropdown will be displayed as "Country".

TEXTBOX

<:input:text (name=city) :>

SUBMIT BUTTON
<:input:submit:>
Displays the submit button
</pre>

h2. Text expressions

<pre>
{: display this if :city: is specified :}
If either a form parameter or variable named city exists, this displays "display this if mumbai is specified" assuming that either a variable or form parameter named city exists, and it's value is "mumbai".
If no such variable exists, the entire expression is rendered as an empty string.

{:city? display this if a city is specified :}
Displays "display this if a city is specified" if a form parameter or variable named city exists. If not, the entire expression is rendered as an empty string.
</pre>

h2. Side-by-side panel formatting for tables

<pre>
On the line before each table, put the following tag:
<:sidebyside:>

After all the side-by-side tables, put this tag:
<:sidebyside:end>
</pre>

h2. CSV format

To display a single query in csv format:

* give the query an id. e.g. [:peopledata (id=testid) select * from people :]
* formulate the url like this: http://hostname:port/page/pagename?id=testid&format=csv

If you wish to change the quote, line separator or format separator, use the parameters in the url below:
http://hostname:port/page/pagename?id=testid&format=csv&col_separator=%7C&quote="&line_separator=$

This url specifies The line separator as $, and the quote as ". The column separator is given as %7C, which is the url encoded value of the | character. Not all symbols need to be encoded like this. It is necessary only if the application displays an error. 


h2. ERB notes

<pre>
class ExecutionContext

what should work inline in pages

	query = 'select country, count(*) count from orders group by country'
	ds['sdhbll'].query(query).ds['mdhbll'].query()

	collect('select country, count(*) count from orders group by country').from('sdhbll', 'mdhbll', 'bhbll').display(:pie)
	query = 'select country, count(*) count from orders group by country'
	q('sdhbll', query).q('mdhbll', query).q('bhbll', query).display(:pie)
end
</pre>
END

	@page = {
		'content' => RedCloth.new(help_text).to_html
	}

	haml :show_page
end
