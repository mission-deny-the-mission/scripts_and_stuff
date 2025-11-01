# Puppet manifest to install ktransformers and configure for CPU inference
# KTransformers CPU Setup Class
class ktransformers_cpu {
  
  # Install required system packages
  $system_packages = [
    'git',
    'wget',
    'curl',
    'build-essential',
    'cmake',
    'libnuma-dev',
    'numactl',
    'python3',
    'python3-pip',
    'python3-venv',
    'pkg-config',
  ]
  
  package { $system_packages:
    ensure => installed,
  }
  
  # Download Miniconda if not present
  exec { 'download_miniconda':
    command => '/usr/bin/wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh',
    creates => '/tmp/miniconda.sh',
    require => Package['wget'],
    path    => ['/usr/bin', '/bin'],
  }
  
  # Install Miniconda
  exec { 'install_miniconda':
    command => '/bin/bash /tmp/miniconda.sh -b -p /opt/miniconda3',
    creates => '/opt/miniconda3',
    require => Exec['download_miniconda'],
    path    => ['/usr/bin', '/bin'],
  }
  
  # Ensure conda bin is in PATH
  file { '/etc/profile.d/conda.sh':
    ensure  => file,
    content => "export PATH=\"/opt/miniconda3/bin:\$PATH\"\n",
    mode    => '0644',
  }
  
  # Create conda environment for ktransformers CPU
  exec { 'create_ktransformers_conda_env':
    command => '/opt/miniconda3/bin/conda create -n kt-cpu python=3.11 -y',
    creates => '/opt/miniconda3/envs/kt-cpu',
    require => Exec['install_miniconda'],
    path    => ['/opt/miniconda3/bin', '/usr/bin', '/bin'],
    environment => ['PATH=/opt/miniconda3/bin:/usr/bin:/bin'],
  }
  
  # Clone ktransformers repository
  exec { 'clone_ktransformers':
    command => '/usr/bin/git clone https://github.com/kvcache-ai/ktransformers.git /opt/ktransformers',
    creates => '/opt/ktransformers',
    require => [Package['git'], Exec['create_ktransformers_conda_env']],
    path    => ['/usr/bin', '/bin'],
  }
  
  # Initialize and update git submodules
  exec { 'init_ktransformers_submodules':
    command => '/usr/bin/git submodule update --init --recursive',
    cwd     => '/opt/ktransformers',
    creates => '/opt/ktransformers/.git/modules',
    require => Exec['clone_ktransformers'],
    path    => ['/usr/bin', '/bin'],
  }
  
  # Upgrade pip in conda environment
  exec { 'upgrade_pip_ktransformers':
    command => '/opt/miniconda3/envs/kt-cpu/bin/pip install --upgrade pip setuptools wheel',
    require => Exec['create_ktransformers_conda_env'],
    path    => ['/opt/miniconda3/envs/kt-cpu/bin', '/usr/bin', '/bin'],
    environment => ['PATH=/opt/miniconda3/envs/kt-cpu/bin:/usr/bin:/bin'],
  }
  
  # Install ktransformers dependencies
  exec { 'install_ktransformers_deps':
    command => '/opt/miniconda3/envs/kt-cpu/bin/pip install torch numpy',
    require => Exec['upgrade_pip_ktransformers'],
    path    => ['/opt/miniconda3/envs/kt-cpu/bin', '/usr/bin', '/bin'],
    environment => ['PATH=/opt/miniconda3/envs/kt-cpu/bin:/usr/bin:/bin'],
  }
  
  # Build and install ktransformers for CPU
  exec { 'install_ktransformers_cpu':
    command => '/bin/bash install.sh',
    cwd     => '/opt/ktransformers',
    require => [Exec['init_ktransformers_submodules'], Exec['install_ktransformers_deps']],
    path    => ['/opt/miniconda3/envs/kt-cpu/bin', '/usr/bin', '/bin', '/opt/miniconda3/bin'],
    environment => [
      'PATH=/opt/miniconda3/envs/kt-cpu/bin:/opt/miniconda3/bin:/usr/bin:/bin',
      'USE_NUMA=1',
      'USE_CPU=1',
    ],
    timeout => 1800,  # 30 minutes timeout for build
  }
  
  # Create ktransformers environment configuration script
  file { '/etc/profile.d/ktransformers.sh':
    ensure  => file,
    content => @(EOT)
# KTransformers CPU Configuration
export PATH="/opt/miniconda3/bin:$PATH"
export CONDA_PREFIX="/opt/miniconda3/envs/kt-cpu"

# CPU inference settings
export USE_CPU=1
export USE_NUMA=1

# Activate conda environment
source /opt/miniconda3/bin/activate kt-cpu
|| EOT
    mode    => '0644',
    require => Exec['install_ktransformers_cpu'],
  }
  
  # Create activation script for easy use
  file { '/usr/local/bin/ktransformers-activate':
    ensure  => file,
    content => @(EOT)
#!/bin/bash
# Activate KTransformers CPU environment
source /opt/miniconda3/bin/activate kt-cpu
source /etc/profile.d/ktransformers.sh
echo "KTransformers CPU environment activated!"
|| EOT
    mode    => '0755',
    require => File['/etc/profile.d/ktransformers.sh'],
  }
  
  # Verify installation
  exec { 'verify_ktransformers_installation':
    command => '/opt/miniconda3/envs/kt-cpu/bin/python -c "import ktransformers; print(\'KTransformers installed successfully\')"',
    require => File['/etc/profile.d/ktransformers.sh'],
    path    => ['/opt/miniconda3/envs/kt-cpu/bin', '/usr/bin', '/bin'],
    environment => ['PATH=/opt/miniconda3/envs/kt-cpu/bin:/usr/bin:/bin'],
    logoutput => true,
  }
}

# Apply the class
include ktransformers_cpu

