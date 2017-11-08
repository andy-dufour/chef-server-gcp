require 'chef-vault'

begin
  infra_secrets = ChefVault::Item.load(node['cluster_name'], 'automate')
rescue
  Chef::Log.warn("Could not find #{node['cluster_name']} vault item.")
  infra_secrets = Mash.new
  infra_secrets['chef_secrets'] = ''
  infra_secrets['migration_level'] = ''
end

directory '/etc/opscode' do
  owner 'root'
  group 'root'
  mode '0755'
  recursive true
  action :create
end

directory '/var/opt/opscode/upgrades' do
  owner 'root'
  group 'root'
  mode '0755'
  recursive true
  action :create
end

file '/etc/opscode/private-chef-secrets.json' do
  content infra_secrets['chef_secrets']
  owner 'root'
  group 'root'
  mode 0600
end

file '/var/opt/opscode/upgrades/migration-level' do
  content infra_secrets['migration_level']
  owner 'root'
  group 'root'
  mode 0600
end
