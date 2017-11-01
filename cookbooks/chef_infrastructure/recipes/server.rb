
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

# HA mode requires sql-backed storage for bookshelf.

bookshelf['storage_type'] = :sql

# RabbitMQ settings

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

chef_user 'delivery' do
  first_name 'Delivery'
  last_name 'User'
  email 'delivery@services.com'
  password 'delivery'
  key_path "#{install_dir}/.chef/delivery.pem"
end

chef_org 'delivery' do
  org_full_name 'Delivery Organization'
  key_path "#{install_dir}/.chef/delivery-validator.pem"
  admins %w( delivery )
end

file "#{install_dir}/.chef/knife.rb" do
  content "
current_dir = File.dirname(__FILE__)
node_name                \"delivery\"
client_key               \"\#\{current_dir\}/delivery.pem\"
chef_server_url          \"https://#{node['fqdn']}/organizations/delivery\"
cookbook_path            [\"#{install_dir}/cookbooks\"]
ssl_verify_mode          :verify_none
validation_key           \"/nonexist\"
"
end

builder_key = OpenSSL::PKey::RSA.new(2048)

directory "#{install_dir}/data_bags" do
  owner 'root'
  group 'root'
  mode 0o0700
  action :create
end

ruby_block 'write_automate_databag' do
  block do

    infra_secrets = Mash.new

    infra_secrets['validator_pem'] = ::File.read("#{install_dir}/.chef/delivery-validator.pem")
    infra_secrets['user_pem'] = ::File.read("#{install_dir}/.chef/delivery.pem")
    infra_secrets['builder_pem'] = builder_key.to_pem
    infra_secrets['builder_pub'] = "ssh-rsa #{[builder_key.to_blob].pack('m0')}"

    ::File.write("#{install_dir}/data_bags/automate.json", infra_secrets.to_json)
    ::File.chmod(600, "#{install_dir}/data_bags/automate.json")
  end
  not_if { ::File.exist?("#{install_dir}/data_bags/automate.json") }
end

execute 'create_automate_automate_vault_item' do
  command "knife vault create automate automate -J \"#{install_dir}/data_bags/automate.json\" -A \"delivery\" -M client"
  cwd install_dir
  sensitive true
  not_if 'knife vault isvault automate automate -M client'
end

execute 'create_automate_password_vault_item' do
  command "knife vault create automate password '{\"password\"\:\"\"}' -A \"delivery\" -M client"
  cwd install_dir
  sensitive true
  not_if 'knife vault isvault automate password -M client'
end
