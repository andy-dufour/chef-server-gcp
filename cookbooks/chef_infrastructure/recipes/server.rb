
automate_db = begin
                data_bag(node['cluster_name'])
              rescue Net::HTTPServerException, Chef::Exceptions::InvalidDataBagPath
                nil # empty array for length comparison
              end

if automate_db
  include_recipe 'chef_infrastructure::_more_frontends'
end

chef_server node['fqdn'] do
  version :latest
  config <<-EOS
# Specify that postgresql is an external database, and provide the
# VIP of this cluster.  This prevents the chef-server instance
# from creating it's own local postgresql instance.

postgresql['external'] = true
postgresql['vip'] = '#{node['chef_server']['postgresql']['vip']}'
postgresql['db_superuser'] = '#{node['chef_server']['postgresql']['db_su']}'
postgresql['db_superuser_password'] = '#{node['chef_server']['postgresql']['db_su_pw']}'

# These settings ensure that we use remote elasticsearch
# instead of local solr for search.  This also
# set search_queue_mode to 'batch' to remove the indexing
# dependency on rabbitmq, which is not supported in this HA configuration.

opscode_solr4['external'] = true
opscode_solr4['external_url'] = 'http://#{node['chef_server']['elasticsearch']['vip']}:9200'
opscode_erchef['search_provider'] = 'elasticsearch'
opscode_erchef['search_queue_mode'] = 'batch'
opscode_erchef['db_pool_size'] = 10

# HA mode requires sql-backed storage for bookshelf.

bookshelf['storage_type'] = :sql
bookshelf['db_pool_size'] = 10
# RabbitMQ settings

oc_bifrost['db_pool_size'] = 10

rabbitmq['enable'] = false
rabbitmq['management_enabled'] = false
rabbitmq['queue_length_monitor_enabled'] = false

# Opscode Expander
#
# opscode-expander isn't used when the search_queue_mode is batch.  It
# also doesn't support the elasticsearch backend.
opscode_expander['enable'] = false

# Prevent startup failures due to missing rabbit host

dark_launch['actions'] = false

# Cookbook Caching

opscode_erchef['nginx_bookshelf_caching'] = :on
opscode_erchef['s3_url_expiry_window_size'] = '50%'
EOS
  addons manage: { version: '2.4.3' }
  accept_license true
end

install_dir = "#{ENV['HOME']}/chef"

directory "#{install_dir}/.chef" do
  recursive true
  action :create
end

chef_gem 'chef-vault' do
  action :install
  compile_time true
end

unless automate_db
  include_recipe 'chef_infrastructure::_first_frontend'
end
