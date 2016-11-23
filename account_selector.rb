require 'yaml'
require 'active_support/core_ext/hash/keys'

class AccountSelector
  @@accounts = {}

  def self.select(account, identity=:admin, options={})
    load_accounts(options.delete(:path))

    # puts @@accounts.inspect

    begin
      username = @@accounts[account][:username]
    rescue NoMethodError
      raise "No such account #{ account }"
    else
      raise "No username specified for #{ account }" unless username
    end

    auth_hash = @@accounts[account][identity].clone || {}
    aux_hash = {}
    
    [:tokens, :indexes].each do |key|
      v = auth_hash.delete(key)
      aux_hash[key] = v if options[:"with_#{ key }"]
    end

    auth_hash.merge!(username: username)
    [:mongo, :billing_start].each do |key|
      aux_hash.merge!(key => @@accounts[account][key]) if options[:"with_#{ key }"]
    end

    unless aux_hash.empty?
      return auth_hash, aux_hash
    else
      return auth_hash
    end    
  end

  ## possible formats
  ##   identity1 index1 (looks for account: default, identity: identity1, index: index1)
  ##   identity1 index1 index2 index3 (multiple indexes in account: default)
  ##   myaccount:identity1 index1 index2 (multiple indexes in account: myaccount)
  ##   myaccount:identity1 index1 index2 mysecondaccount:identity2 indexA indexB (multiple indexes in account: mysecondaccount)
  def self.select_from_commandline(account_selectors, options={})
    account, identity = nil, nil
    first = true
    selected_config = {}
    account_selectors.each do |selector|
      if first || selector.include?(":")
        identity, account = selector.split(":").reverse.collect { |s| s.to_sym }
        account ||= :default
        config, info = self.select(account, identity, options)

        selected_config[account] ||= {} 
        selected_config[account][identity] ||= {}

        selected_config[account][identity][:config] = config
        selected_config[account][identity][:info] = info
        selected_config[account][identity][:selected_indexes] ||= []
        first = false
      else
        selected_config[account][identity][:selected_indexes] << selector.to_sym
        next
      end
    end
    return selected_config
  end

  def self.select!(*args)
    @@accounts = {}
    select(*args)
  end

  def evaluate_commandline_args(args)
    account = :default
    account, args[0] = args.first.split(":") if args.first.include?(":")
    account = account.to_sym
    args.collect! { |a| a.to_sym }
    identity, *indexes = args
    return account, identity, indexes
  end

protected
  def self.load_accounts(path_to_identity_file=nil)
    path_to_identity_file ||= "./identities.yml"
    return unless @@accounts.empty?
    path = File.expand_path(path_to_identity_file)
    @@accounts = YAML.load_file(path)
    @@accounts.deep_symbolize_keys!
  end
end