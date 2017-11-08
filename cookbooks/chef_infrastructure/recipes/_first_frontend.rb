
install_dir = "#{ENV['HOME']}/chef"

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

file "/tmp/delivery.pem" do
  mode 644
  content lazy { ::File.read("#{install_dir}/.chef/delivery.pem") }
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
  mode 0700
  action :create
end

ruby_block 'write_automate_databag' do
  block do
    infra_secrets = Mash.new

    infra_secrets['validator_pem'] = ::File.read("#{install_dir}/.chef/delivery-validator.pem")
    infra_secrets['user_pem'] = ::File.read("#{install_dir}/.chef/delivery.pem")
    infra_secrets['builder_pem'] = builder_key.to_pem
    infra_secrets['builder_pub'] = "ssh-rsa #{[builder_key.to_blob].pack('m0')}"
    infra_secrets['chef_secrets'] = ::File.read('/etc/opscode/private-chef-secrets.json')
    infra_secrets['migration_level'] = ::File.read('/var/opt/opscode/upgrades/migration-level')

    ::File.write("#{install_dir}/data_bags/automate.json", infra_secrets.to_json)
    ::File.chmod(0600, "#{install_dir}/data_bags/automate.json")
  end
  not_if { ::File.exist?("#{install_dir}/data_bags/automate.json") }
end

execute 'create_automate_automate_vault_item' do
  command "knife vault create #{node['cluster_name']} automate -J \"#{install_dir}/data_bags/automate.json\" -A \"delivery\" -M client"
  cwd "/tmp/"
  sensitive true
  not_if "knife vault isvault #{node['cluster_name']} automate -M client"
end

execute 'create_automate_password_vault_item' do
  command "knife vault create #{node['cluster_name']} password '{\"password\"\:\"\"}' -A \"delivery\" -M client"
  cwd "/tmp/"
  sensitive true
  not_if "knife vault isvault #{node['cluster_name']} password -M client"
end
