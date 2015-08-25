def data_source
  DataSourceSQLiteStore.new
end

def data_sources
  DataSourceSQLiteStore.new
end

class DataSourceSQLiteStore < SQLiteStore
  def load(data_source_name)
    data_source = db[:data_sources].where(data_source_name: data_source_name).first
    self.close
    if data_source
    then
      to_displayable_hash(data_source_name, get_attributes_hash(data_source_name))
    else
      nil
    end
  end

  def get_attributes_hash(data_source_name)
    data_source_attributes = db[:data_source_attributes].where(data_source_name: data_source_name)
    attributes_hash = {}
    data_source_attributes.each{|attr| attributes_hash[param_to_sym(attr[:attribute_name])] = attr[:attribute_value] }
    self.close
    attributes_hash
  end

  def to_hash(data_source_name, attributes_hash)
    result = {}
    result[param_to_sym(data_source_name)] = attributes_hash
    result
  end

  def to_displayable_hash(data_source_name, attributes_hash)
    result = {}
    result[param_to_sym(data_source_name)] = attr_hash_to_string(attributes_hash)
    result
  end

  def save(data_source_name, attributes, permissions, creator)
    existing_data_source = load(data_source_name)

    if existing_data_source != nil
    then
      db[:data_source_attributes].where(data_source_name: data_source_name).delete
      db[:data_source_permissions].where(data_source_name: data_source_name).delete
    else
      db[:data_sources].insert(data_source_name: data_source_name, creator: creator)
    end

    attributes.each do |name, value|
      unless name.nil?
        db[:data_source_attributes].insert(data_source_name: data_source_name,
                                           attribute_name: name.to_s,
                                           attribute_value: value.to_s)
      end
    end

    permissions.each do |entity, table|
      table.each do |entity_name, permission|
        db[:data_source_permissions].insert(data_source_name: data_source_name,
                                            entity: entity.to_s,
                                            entity_name: entity_name.to_s,
                                            permission: permission.to_s)
      end
    end

    self.close
  end

  def list
    data_sources = {}
    db[:data_sources].collect do |data_source|
      data_source_name = data_source[:data_source_name]
      data_source_attributes = get_attributes_hash(data_source_name)
      data_sources[param_to_sym(data_source_name)] = data_source_attributes
    end
    self.close
    data_sources
  end

  def list_created_by(username)
    data_sources_hash = {}
    data_sources = db[:data_sources].where(creator: username)
    data_sources.each do |data_source|
      data_source_name = data_source[:data_source_name]
      data_source_attributes = get_attributes_hash(data_source_name)
      data_sources_hash[param_to_sym(data_source_name)] = data_source_attributes
    end
    self.close
    data_sources_hash
  end

  def delete(data_source_name)
    db[:data_sources].where(data_source_name: data_source_name).delete
    db[:data_source_attributes].where(data_source_name: data_source_name).delete
    self.close
  end
end

def attr_string_to_hash(attributes_string)
  attributes_hash = {}

  attributes_string.split(';').each do |attribute|
    attribute_literals = attribute.split('=')
    attributes_hash[param_to_sym(attribute_literals.first)] = attribute_literals.last
  end

  attributes_hash
end

def attr_hash_to_string(attributes_hash)
  attributes_string = ''

  attributes_hash.each do |name, value|
    attributes_string += "#{name}=#{value};"
  end

  attributes_string
end

def get_data_source_edit_link(url)
  uri = URI.parse(url)
  uri.path += '/edit'
  uri.to_s
end