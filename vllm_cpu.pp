# Puppet manifest to install vLLM and configure for CPU inference
# vLLM CPU Setup Class
class vllm_cpu {
  
  # Install required system packages
  $system_packages = [
    'git',
    'wget',
    'curl',
    'build-essential',
    'cmake',
    'gcc-12',
    'g++-12',
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
  
  # Configure GCC/G++ 12 as default (required for vLLM CPU)
  exec { 'configure_gcc12':
    command => '/usr/bin/update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 10 --slave /usr/bin/g++ g++ /usr/bin/g++-12',
    unless  => '/usr/bin/update-alternatives --display gcc | grep -q gcc-12',
    require => Package['gcc-12', 'g++-12'],
    path    => ['/usr/bin', '/bin'],
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
  
  # Create conda environment for vLLM CPU
  exec { 'create_vllm_conda_env':
    command => '/opt/miniconda3/bin/conda create -n vllm-cpu python=3.11 -y',
    creates => '/opt/miniconda3/envs/vllm-cpu',
    require => Exec['install_miniconda'],
    path    => ['/opt/miniconda3/bin', '/usr/bin', '/bin'],
    environment => ['PATH=/opt/miniconda3/bin:/usr/bin:/bin'],
  }
  
  # Clone vLLM repository
  exec { 'clone_vllm':
    command => '/usr/bin/git clone https://github.com/vllm-project/vllm.git /opt/vllm',
    creates => '/opt/vllm',
    require => [Package['git'], Exec['create_vllm_conda_env']],
    path    => ['/usr/bin', '/bin'],
  }
  
  # Upgrade pip and install build dependencies
  exec { 'upgrade_pip_vllm':
    command => '/opt/miniconda3/envs/vllm-cpu/bin/pip install --upgrade pip wheel packaging ninja "setuptools>=49.4.0" numpy',
    require => Exec['create_vllm_conda_env'],
    path    => ['/opt/miniconda3/envs/vllm-cpu/bin', '/usr/bin', '/bin'],
    environment => ['PATH=/opt/miniconda3/envs/vllm-cpu/bin:/usr/bin:/bin'],
  }
  
  # Install vLLM CPU requirements
  exec { 'install_vllm_cpu_requirements':
    command => '/opt/miniconda3/envs/vllm-cpu/bin/pip install -v -r requirements-cpu.txt --extra-index-url https://download.pytorch.org/whl/cpu',
    cwd     => '/opt/vllm',
    require => [Exec['clone_vllm'], Exec['upgrade_pip_vllm']],
    path    => ['/opt/miniconda3/envs/vllm-cpu/bin', '/usr/bin', '/bin'],
    environment => ['PATH=/opt/miniconda3/envs/vllm-cpu/bin:/usr/bin:/bin'],
    timeout => 1800,  # 30 minutes timeout
  }
  
  # Build and install vLLM for CPU
  exec { 'install_vllm_cpu':
    command => '/bin/bash -c "cd /opt/vllm && VLLM_TARGET_DEVICE=cpu /opt/miniconda3/envs/vllm-cpu/bin/python setup.py install"',
    require => [Exec['install_vllm_cpu_requirements'], Exec['configure_gcc12']],
    path    => ['/opt/miniconda3/envs/vllm-cpu/bin', '/usr/bin', '/bin'],
    environment => [
      'PATH=/opt/miniconda3/envs/vllm-cpu/bin:/usr/bin:/bin',
      'VLLM_TARGET_DEVICE=cpu',
      'CC=gcc-12',
      'CXX=g++-12',
    ],
    timeout => 1800,  # 30 minutes timeout for build
  }
  
  # Create vLLM environment configuration script
  file { '/etc/profile.d/vllm.sh':
    ensure  => file,
    content => @(EOT)
# vLLM CPU Configuration
export PATH="/opt/miniconda3/bin:$PATH"
export CONDA_PREFIX="/opt/miniconda3/envs/vllm-cpu"

# vLLM CPU inference settings
export VLLM_TARGET_DEVICE=cpu

# KV Cache space (adjust based on your system memory)
# Default: 40 GiB - modify as needed
export VLLM_CPU_KVCACHE_SPACE=${VLLM_CPU_KVCACHE_SPACE:-40}

# OpenMP thread binding (adjust based on your CPU cores)
# Example for 64 cores: "0-31|32-63"
# Leave unset to use all available cores
# export VLLM_CPU_OMP_THREADS_BIND="0-31"

# Activate conda environment
source /opt/miniconda3/bin/activate vllm-cpu
|| EOT
    mode    => '0644',
    require => Exec['install_vllm_cpu'],
  }
  
  # Create activation script for easy use
  file { '/usr/local/bin/vllm-activate':
    ensure  => file,
    content => @(EOT)
#!/bin/bash
# Activate vLLM CPU environment
source /opt/miniconda3/bin/activate vllm-cpu
source /etc/profile.d/vllm.sh
echo "vLLM CPU environment activated!"
echo "KV Cache Space: ${VLLM_CPU_KVCACHE_SPACE:-40} GiB"
echo "To start vLLM server, use: vllm serve <model-name> -tp=<num> --distributed-executor-backend mp"
|| EOT
    mode    => '0755',
    require => File['/etc/profile.d/vllm.sh'],
  }
  
  # Verify installation
  exec { 'verify_vllm_installation':
    command => '/opt/miniconda3/envs/vllm-cpu/bin/python -c "import vllm; print(\'vLLM installed successfully\')"',
    require => File['/etc/profile.d/vllm.sh'],
    path    => ['/opt/miniconda3/envs/vllm-cpu/bin', '/usr/bin', '/bin'],
    environment => ['PATH=/opt/miniconda3/envs/vllm-cpu/bin:/usr/bin:/bin'],
    logoutput => true,
  }
}

# Apply the class
include vllm_cpu
