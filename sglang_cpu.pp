# Puppet manifest to install SGLang and configure for CPU inference
# SGLang CPU Setup Class
class sglang_cpu {
  
  # Install required system packages
  $system_packages = [
    'git',
    'wget',
    'curl',
    'build-essential',
    'cmake',
    'libsqlite3-dev',
    'libtbb-dev',
    'libnuma-dev',
    'numactl',
    'python3',
    'python3-pip',
    'python3-venv',
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

  # Create conda cache directory with proper permissions
  file { '/root/.cache':
    ensure => directory,
    mode   => '0755',
  }

  file { '/root/.cache/conda-anaconda-tos':
    ensure  => directory,
    mode    => '0755',
    require => File['/root/.cache'],
  }
  
  # Ensure conda bin is in PATH
  file { '/etc/profile.d/conda.sh':
    ensure  => file,
    content => "export PATH=\"/opt/miniconda3/bin:\$PATH\"\n",
    mode    => '0644',
  }
  
  # Accept conda Terms of Service for main channel
  exec { 'accept_conda_tos_main':
    command     => '/usr/bin/env HOME=/root /opt/miniconda3/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main',
    require     => [Exec['install_miniconda'], File['/root/.cache/conda-anaconda-tos']],
    path        => ['/opt/miniconda3/bin', '/usr/bin', '/bin'],
    unless      => '/usr/bin/test -f /root/.cache/conda-anaconda-tos/3c9d068aa053e2a1c4313fe3391b7a8ee57c4fbd09c4e8aeae49ef333a740150.cache',
  }

  # Accept conda Terms of Service for r channel
  exec { 'accept_conda_tos_r':
    command     => '/usr/bin/env HOME=/root /opt/miniconda3/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r',
    require     => [Exec['install_miniconda'], File['/root/.cache/conda-anaconda-tos']],
    path        => ['/opt/miniconda3/bin', '/usr/bin', '/bin'],
    unless      => '/usr/bin/test -f /root/.cache/conda-anaconda-tos/8c054ac91082b2ed4862701ed278dc96a78db796db69dedc296e13baab307527.cache',
  }

  # Initialize conda for shell usage
  exec { 'init_conda':
    command => '/usr/bin/env HOME=/root /opt/miniconda3/bin/conda init bash',
    require => [Exec['accept_conda_tos_main'], Exec['accept_conda_tos_r']],
    path    => ['/opt/miniconda3/bin', '/usr/bin', '/bin'],
    creates => '/root/.condarc',
  }

  # Create conda environment for SGLang CPU
  exec { 'create_sglang_conda_env':
    command => '/usr/bin/env HOME=/root /opt/miniconda3/bin/conda create -n sgl-cpu python=3.12 -y',
    creates => '/opt/miniconda3/envs/sgl-cpu',
    require => [Exec['install_miniconda'], Exec['accept_conda_tos_main'], Exec['accept_conda_tos_r'], Exec['init_conda']],
    path    => ['/opt/miniconda3/bin', '/usr/bin', '/bin'],
  }
  
  # Clone SGLang repository
  exec { 'clone_sglang':
    command => '/usr/bin/git clone https://github.com/sgl-project/sglang.git /opt/sglang',
    creates => '/opt/sglang',
    require => [Package['git'], Exec['create_sglang_conda_env']],
    path    => ['/usr/bin', '/bin'],
  }
  
  # Upgrade pip and install intel-openmp in conda environment
  exec { 'upgrade_pip_sglang':
    command => '/opt/miniconda3/envs/sgl-cpu/bin/pip install --upgrade pip setuptools',
    require => Exec['create_sglang_conda_env'],
    path    => ['/opt/miniconda3/envs/sgl-cpu/bin', '/usr/bin', '/bin'],
    environment => ['PATH=/opt/miniconda3/envs/sgl-cpu/bin:/usr/bin:/bin'],
  }
  
  # Install Intel OpenMP
  exec { 'install_intel_openmp':
    command => '/opt/miniconda3/envs/sgl-cpu/bin/pip install intel-openmp',
    require => Exec['upgrade_pip_sglang'],
    path    => ['/opt/miniconda3/envs/sgl-cpu/bin', '/usr/bin', '/bin'],
    environment => ['PATH=/opt/miniconda3/envs/sgl-cpu/bin:/usr/bin:/bin'],
  }
  
  # Install conda dependencies
  exec { 'install_conda_deps':
    command => '/usr/bin/env HOME=/root /opt/miniconda3/bin/conda install -n sgl-cpu -y libsqlite=3.48.0 gperftools tbb libnuma numactl',
    require => Exec['install_intel_openmp'],
    path    => ['/opt/miniconda3/bin', '/usr/bin', '/bin'],
  }
  
  # Install SGLang with CPU support
  exec { 'install_sglang_cpu':
    command => '/opt/miniconda3/envs/sgl-cpu/bin/pip install -e "python[all_cpu]"',
    cwd     => '/opt/sglang',
    require => [Exec['clone_sglang'], Exec['install_conda_deps']],
    path    => ['/opt/miniconda3/envs/sgl-cpu/bin', '/usr/bin', '/bin'],
    environment => ['PATH=/opt/miniconda3/envs/sgl-cpu/bin:/usr/bin:/bin'],
    timeout => 1800,  # 30 minutes timeout for build
  }
  
  # Build CPU backend kernels
  exec { 'build_cpu_kernels':
    command => '/bin/bash -c "cd /opt/sglang/sgl-kernel && cp pyproject_cpu.toml pyproject.toml && /opt/miniconda3/envs/sgl-cpu/bin/pip install -v ."',
    require => Exec['install_sglang_cpu'],
    path    => ['/opt/miniconda3/envs/sgl-cpu/bin', '/usr/bin', '/bin'],
    environment => ['PATH=/opt/miniconda3/envs/sgl-cpu/bin:/usr/bin:/bin'],
    timeout => 1800,  # 30 minutes timeout for build
  }
  
  # Create SGLang environment configuration script
  file { '/etc/profile.d/sglang.sh':
    ensure  => file,
    content => "# SGLang CPU Configuration\nexport PATH=\"/opt/miniconda3/bin:\$PATH\"\nexport CONDA_PREFIX=\"/opt/miniconda3/envs/sgl-cpu\"\nexport SGLANG_USE_CPU_ENGINE=1\n\n# Intel OpenMP and memory allocators\nif [ -f \"\$CONDA_PREFIX/lib/libiomp5.so\" ]; then\n  export LD_PRELOAD=\"\${LD_PRELOAD}:\$CONDA_PREFIX/lib/libiomp5.so\"\nfi\n\nif [ -f \"\$CONDA_PREFIX/lib/libtcmalloc.so\" ]; then\n  export LD_PRELOAD=\"\${LD_PRELOAD}:\$CONDA_PREFIX/lib/libtcmalloc.so\"\nfi\n\nif [ -f \"\$CONDA_PREFIX/lib/libtbbmalloc.so.2\" ]; then\n  export LD_PRELOAD=\"\${LD_PRELOAD}:\$CONDA_PREFIX/lib/libtbbmalloc.so.2\"\nfi\n\n# Activate conda environment\nsource /opt/miniconda3/bin/activate sgl-cpu\n",
    mode    => '0644',
    require => Exec['build_cpu_kernels'],
  }
  
  # Create activation script for easy use
  file { '/usr/local/bin/sglang-activate':
    ensure  => file,
    content => "#!/bin/bash\n# Activate SGLang CPU environment\nsource /opt/miniconda3/bin/activate sgl-cpu\nsource /etc/profile.d/sglang.sh\necho \"SGLang CPU environment activated!\"\n",
    mode    => '0755',
    require => File['/etc/profile.d/sglang.sh'],
  }
  
  # Verify installation
  exec { 'verify_sglang_installation':
    command => '/opt/miniconda3/envs/sgl-cpu/bin/python -c "import sglang; print(\'SGLang installed successfully\')"',
    require => File['/etc/profile.d/sglang.sh'],
    path    => ['/opt/miniconda3/envs/sgl-cpu/bin', '/usr/bin', '/bin'],
    environment => ['PATH=/opt/miniconda3/envs/sgl-cpu/bin:/usr/bin:/bin'],
    logoutput => true,
  }
}

# Apply the class
include sglang_cpu
