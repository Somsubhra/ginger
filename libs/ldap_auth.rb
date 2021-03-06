def ldap_authenticate(username, password)
  name, domain = username.split('@')
  auth_conf = get_conf[:authentication][param_to_sym(domain)]

  if name == '' or password == ''
    return {status: 'failed'}
  end

  if auth_conf
    if auth_conf[:type] == 'ldap'

      if auth_conf[:ldap_server] == 'localhost'
        return {status: 'authenticated'}
      end

      ldap = Net::LDAP.new

      ldap.host = auth_conf[:ldap_server]
      ldap.port = auth_conf[:ldap_port] || 389
      ldap.auth(name, password)

      if ldap.bind
        return {status: 'authenticated'}
      else
        return {status: 'failed'}
      end
    end
  end

  {status: 'error', message: 'Authentication method not found.'}
end

