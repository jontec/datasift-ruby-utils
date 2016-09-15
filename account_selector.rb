require 'yaml'
require 'active_support/core_ext/hash/keys.rb'

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
      billing_start = @@accounts[account][:billing_start]
    end

    auth_hash = @@accounts[account][identity].clone || {}
    aux_hash = {}
    
    [:tokens, :indexes].each do |key|
      v = auth_hash.delete(key)
      aux_hash[key] = v if options[:"with_#{ key }"]
    end

    auth_hash.merge!(username: username)
    aux_hash.merge!(billing_start: billing_start) if options[:with_billing_start]

    unless aux_hash.empty?
      return auth_hash, aux_hash
    else
      return auth_hash
    end    
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