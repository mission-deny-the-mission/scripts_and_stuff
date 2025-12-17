# Puppet manifest to install and configure LiteLLM as a service
# Includes Web UI and PostgreSQL configuration database
class litellm (
  String $master_key = 'sk-litellm-master-key-change-me',
  String $ui_username = 'admin',
  String $ui_password = 'admin123',
  Integer $proxy_port = 4000,
  String $db_name = 'litellm',
  String $db_user = 'litellm',
  String $db_password = 'litellm_password_change_me',
  String $install_dir = '/opt/litellm',
  String $config_dir = '/etc/litellm',
  String $data_dir = '/var/lib/litellm',
  String $log_dir = '/var/log/litellm',
) {

  # Install required system packages
  $system_packages = [
    'python3',
    'python3-pip',
    'python3-venv',
    'python3-dev',
    'build-essential',
    'libpq-dev',
    'postgresql',
    'postgresql-contrib',
    'curl',
    'wget',
  ]

  package { $system_packages:
    ensure => installed,
  }

  # Ensure PostgreSQL service is running
  service { 'postgresql':
    ensure  => running,
    enable  => true,
    require => Package['postgresql'],
  }

  # Create PostgreSQL database and user for LiteLLM
  exec { 'create_litellm_db_user':
    command => "/usr/bin/sudo -u postgres psql -c \"CREATE USER ${db_user} WITH PASSWORD '${db_password}';\"",
    unless  => "/usr/bin/sudo -u postgres psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='${db_user}'\" | grep -q 1",
    require => Service['postgresql'],
    path    => ['/usr/bin', '/bin'],
  }

  exec { 'create_litellm_database':
    command => "/usr/bin/sudo -u postgres psql -c \"CREATE DATABASE ${db_name} OWNER ${db_user};\"",
    unless  => "/usr/bin/sudo -u postgres psql -tAc \"SELECT 1 FROM pg_database WHERE datname='${db_name}'\" | grep -q 1",
    require => Exec['create_litellm_db_user'],
    path    => ['/usr/bin', '/bin'],
  }

  # Grant privileges to litellm user
  exec { 'grant_litellm_privileges':
    command     => "/usr/bin/sudo -u postgres psql -c \"GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};\"",
    refreshonly => true,
    subscribe   => Exec['create_litellm_database'],
    path        => ['/usr/bin', '/bin'],
  }

  # Create litellm system user
  user { 'litellm':
    ensure     => present,
    system     => true,
    home       => $data_dir,
    shell      => '/bin/false',
    managehome => false,
  }

  group { 'litellm':
    ensure => present,
    system => true,
  }

  # Create required directories
  file { [$install_dir, $config_dir, $data_dir, $log_dir]:
    ensure  => directory,
    owner   => 'litellm',
    group   => 'litellm',
    mode    => '0755',
    require => [User['litellm'], Group['litellm']],
  }

  # Create Python virtual environment
  exec { 'create_litellm_venv':
    command => "/usr/bin/python3 -m venv ${install_dir}/venv",
    creates => "${install_dir}/venv",
    require => [Package['python3-venv'], File[$install_dir]],
    path    => ['/usr/bin', '/bin'],
  }

  # Upgrade pip in virtual environment
  exec { 'upgrade_litellm_pip':
    command => "${install_dir}/venv/bin/pip install --upgrade pip wheel setuptools",
    require => Exec['create_litellm_venv'],
    path    => ["${install_dir}/venv/bin", '/usr/bin', '/bin'],
    unless  => "${install_dir}/venv/bin/pip --version | grep -q 'pip 2'",
  }

  # Install LiteLLM with proxy and UI support
  exec { 'install_litellm':
    command     => "${install_dir}/venv/bin/pip install 'litellm[proxy]' prisma psycopg2-binary",
    require     => [Exec['upgrade_litellm_pip'], Package['libpq-dev']],
    path        => ["${install_dir}/venv/bin", '/usr/bin', '/bin'],
    environment => ["PATH=${install_dir}/venv/bin:/usr/bin:/bin"],
    timeout     => 600,
    unless      => "${install_dir}/venv/bin/pip show litellm",
  }

  # Set ownership of virtual environment
  exec { 'chown_litellm_venv':
    command => "/bin/chown -R litellm:litellm ${install_dir}",
    require => Exec['install_litellm'],
    path    => ['/bin', '/usr/bin'],
    onlyif  => "/usr/bin/find ${install_dir} ! -user litellm | /bin/grep -q .",
  }

  # Database URL for LiteLLM
  $database_url = "postgresql://${db_user}:${db_password}@localhost:5432/${db_name}"

  # Create LiteLLM configuration file
  $config_yaml_content = "# LiteLLM Proxy Configuration
# Documentation: https://docs.litellm.ai/docs/proxy/configs

model_list:
  # OpenAI Models (uncomment and add your API key)
  # - model_name: gpt-4
  #   litellm_params:
  #     model: openai/gpt-4
  #     api_key: os.environ/OPENAI_API_KEY

  # - model_name: gpt-3.5-turbo
  #   litellm_params:
  #     model: openai/gpt-3.5-turbo
  #     api_key: os.environ/OPENAI_API_KEY

  # Anthropic Models (uncomment and add your API key)
  # - model_name: claude-3-opus
  #   litellm_params:
  #     model: anthropic/claude-3-opus-20240229
  #     api_key: os.environ/ANTHROPIC_API_KEY

  # Local Ollama Models (uncomment if using Ollama)
  # - model_name: llama2
  #   litellm_params:
  #     model: ollama/llama2
  #     api_base: http://localhost:11434

  # Example placeholder model (remove after adding real models)
  - model_name: fake-openai-endpoint
    litellm_params:
      model: openai/fake
      api_key: fake-key
      api_base: https://exampleopenaiendpoint-production.up.railway.app/

general_settings:
  # Master key for admin access
  master_key: ${master_key}

  # Database for storing config, keys, users
  database_url: ${database_url}

  # Enable the Web UI
  ui_access_mode: all

  # Store model info in database
  store_model_in_db: true

litellm_settings:
  # Drop params not supported by specific models
  drop_params: true

# Router settings for load balancing
router_settings:
  routing_strategy: simple-shuffle
  num_retries: 3
  timeout: 30
"

  file { "${config_dir}/config.yaml":
    ensure  => file,
    owner   => 'litellm',
    group   => 'litellm',
    mode    => '0640',
    content => $config_yaml_content,
    require => File[$config_dir],
  }

  # Create environment file for sensitive variables
  $env_content = "# LiteLLM Environment Variables
# Add your API keys and secrets here

# Database
DATABASE_URL=${database_url}

# LiteLLM Master Key
LITELLM_MASTER_KEY=${master_key}

# UI Credentials (for initial setup)
UI_USERNAME=${ui_username}
UI_PASSWORD=${ui_password}

# Provider API Keys (uncomment and fill in as needed)
# OPENAI_API_KEY=sk-...
# ANTHROPIC_API_KEY=sk-ant-...
# AZURE_API_KEY=...
# AZURE_API_BASE=https://your-resource.openai.azure.com/
# AWS_ACCESS_KEY_ID=...
# AWS_SECRET_ACCESS_KEY=...
# AWS_REGION_NAME=us-east-1
# COHERE_API_KEY=...
# HUGGINGFACE_API_KEY=...
# REPLICATE_API_KEY=...
# TOGETHERAI_API_KEY=...
# OPENROUTER_API_KEY=...
# GROQ_API_KEY=...
"

  file { "${config_dir}/env":
    ensure  => file,
    owner   => 'litellm',
    group   => 'litellm',
    mode    => '0600',
    content => $env_content,
    require => File[$config_dir],
  }

  # Create systemd service file
  $systemd_content = "[Unit]
Description=LiteLLM Proxy Server
Documentation=https://docs.litellm.ai/
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=litellm
Group=litellm
WorkingDirectory=${data_dir}

# Environment file with API keys
EnvironmentFile=${config_dir}/env

# Ensure venv binaries are in PATH for Prisma
Environment=PATH=${install_dir}/venv/bin:/usr/local/bin:/usr/bin:/bin
Environment=HOME=${data_dir}

# LiteLLM proxy command
ExecStart=${install_dir}/venv/bin/litellm --config ${config_dir}/config.yaml --port ${proxy_port} --host 0.0.0.0 --detailed_debug

# Restart policy
Restart=always
RestartSec=10
TimeoutStartSec=600
TimeoutStopSec=30

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=litellm

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${data_dir} ${log_dir} ${install_dir}

[Install]
WantedBy=multi-user.target
"

  file { '/etc/systemd/system/litellm.service':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => $systemd_content,
    require => [File["${config_dir}/config.yaml"], File["${config_dir}/env"], Exec['install_litellm']],
    notify  => Exec['systemctl_daemon_reload'],
  }

  # Reload systemd daemon
  exec { 'systemctl_daemon_reload':
    command     => '/bin/systemctl daemon-reload',
    refreshonly => true,
    path        => ['/bin', '/usr/bin'],
  }

  # Find the Prisma schema location (varies by Python version)
  $prisma_schema_path = "${install_dir}/venv/lib/python3.11/site-packages/litellm/proxy/schema.prisma"

  # Fetch Prisma query engine binaries
  exec { 'litellm_prisma_fetch':
    command     => "${install_dir}/venv/bin/python -m prisma py fetch",
    user        => 'litellm',
    environment => [
      "DATABASE_URL=${database_url}",
      "PATH=${install_dir}/venv/bin:/usr/bin:/bin",
      "HOME=${data_dir}",
    ],
    require     => [Exec['install_litellm'], File[$data_dir]],
    path        => ["${install_dir}/venv/bin", '/usr/bin', '/bin'],
    timeout     => 300,
    creates     => "${data_dir}/.cache/prisma-python/binaries",
  }

  # Generate Prisma client
  exec { 'litellm_prisma_generate':
    command     => "${install_dir}/venv/bin/python -m prisma generate --schema=${prisma_schema_path}",
    cwd         => $install_dir,
    user        => 'litellm',
    environment => [
      "DATABASE_URL=${database_url}",
      "PATH=${install_dir}/venv/bin:/usr/bin:/bin",
      "HOME=${data_dir}",
    ],
    require     => [Exec['litellm_prisma_fetch'], Exec['create_litellm_database'], Exec['chown_litellm_venv']],
    path        => ["${install_dir}/venv/bin", '/usr/bin', '/bin'],
    timeout     => 300,
    unless      => "/usr/bin/test -f ${install_dir}/venv/lib/python3.11/site-packages/prisma/schema.prisma",
  }

  # Initialize Prisma database schema
  exec { 'litellm_prisma_db_push':
    command     => "${install_dir}/venv/bin/python -m prisma db push --schema=${prisma_schema_path} --accept-data-loss --skip-generate",
    cwd         => $install_dir,
    user        => 'litellm',
    environment => [
      "DATABASE_URL=${database_url}",
      "PATH=${install_dir}/venv/bin:/usr/bin:/bin",
      "HOME=${data_dir}",
    ],
    require     => [Exec['litellm_prisma_generate']],
    path        => ["${install_dir}/venv/bin", '/usr/bin', '/bin'],
    unless      => "/usr/bin/sudo -u postgres psql -d ${db_name} -tAc \"SELECT 1 FROM information_schema.tables WHERE table_name='LiteLLM_VerificationToken'\" | grep -q 1",
    timeout     => 300,
  }

  # Enable and start LiteLLM service
  service { 'litellm':
    ensure  => running,
    enable  => true,
    require => [
      File['/etc/systemd/system/litellm.service'],
      Exec['systemctl_daemon_reload'],
      Exec['litellm_prisma_db_push'],
    ],
  }

  # Create convenience scripts
  $status_script = "#!/bin/bash
echo \"=== LiteLLM Service Status ===\"
systemctl status litellm --no-pager
echo \"\"
echo \"=== Recent Logs ===\"
journalctl -u litellm -n 20 --no-pager
"

  file { '/usr/local/bin/litellm-status':
    ensure  => file,
    mode    => '0755',
    content => $status_script,
  }

  $logs_script = "#!/bin/bash
journalctl -u litellm -f
"

  file { '/usr/local/bin/litellm-logs':
    ensure  => file,
    mode    => '0755',
    content => $logs_script,
  }

  $cli_script = "#!/bin/bash
# LiteLLM CLI wrapper
source ${install_dir}/venv/bin/activate
litellm \"\$@\"
"

  file { '/usr/local/bin/litellm-cli':
    ensure  => file,
    mode    => '0755',
    content => $cli_script,
  }

  # Create post-installation info file
  $readme_content = "=== LiteLLM Installation Complete ===

Web UI:
  URL: http://localhost:${proxy_port}/ui
  Default credentials: ${ui_username} / ${ui_password}
  Master Key: ${master_key}

API Endpoint:
  Base URL: http://localhost:${proxy_port}
  Health Check: http://localhost:${proxy_port}/health

Configuration Files:
  Main Config: ${config_dir}/config.yaml
  Environment: ${config_dir}/env (API keys go here)

Service Management:
  Start:   sudo systemctl start litellm
  Stop:    sudo systemctl stop litellm
  Restart: sudo systemctl restart litellm
  Status:  sudo systemctl status litellm
  Logs:    sudo journalctl -u litellm -f

Convenience Scripts:
  litellm-status  - Show service status and recent logs
  litellm-logs    - Follow live logs
  litellm-cli     - Run litellm commands

Database:
  PostgreSQL database: ${db_name}
  User: ${db_user}

Next Steps:
  1. Edit ${config_dir}/env and add your API keys
  2. Edit ${config_dir}/config.yaml to configure your models
  3. Restart the service: sudo systemctl restart litellm
  4. Access the Web UI at http://localhost:${proxy_port}/ui

API Usage Example:
  curl http://localhost:${proxy_port}/v1/chat/completions \\
    -H \"Content-Type: application/json\" \\
    -H \"Authorization: Bearer ${master_key}\" \\
    -d '{
      \"model\": \"gpt-3.5-turbo\",
      \"messages\": [{\"role\": \"user\", \"content\": \"Hello!\"}]
    }'

Documentation: https://docs.litellm.ai/
"

  file { "${config_dir}/README.txt":
    ensure  => file,
    owner   => 'litellm',
    group   => 'litellm',
    mode    => '0644',
    content => $readme_content,
    require => Service['litellm'],
  }

  # Output notice
  notify { 'litellm_installed':
    message => "LiteLLM installed! Web UI: http://localhost:${proxy_port}/ui | Config: ${config_dir}/config.yaml | Env: ${config_dir}/env",
    require => Service['litellm'],
  }
}

# Apply the class with default parameters
# To customize, use: class { 'litellm': master_key => 'your-secure-key', ... }
include litellm
