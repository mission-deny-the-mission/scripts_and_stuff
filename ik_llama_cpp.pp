# Puppet manifest to install ik_llama.cpp (llama.cpp fork) for CPU inference
# ik_llama.cpp CPU Setup Class
class ik_llama_cpp {
  
  # Install required system packages
  $system_packages = [
    'git',
    'wget',
    'curl',
    'build-essential',
    'cmake',
    'python3',
    'python3-pip',
    'python3-venv',
    'pkg-config',
  ]
  
  package { $system_packages:
    ensure => installed,
  }
  
  # Clone ik_llama.cpp repository
  exec { 'clone_ik_llama_cpp':
    command => '/usr/bin/git clone https://github.com/ikawrakow/ik_llama.cpp.git /opt/ik_llama.cpp',
    creates => '/opt/ik_llama.cpp',
    require => Package['git'],
    path    => ['/usr/bin', '/bin'],
  }
  
  # Configure CMake build for CPU-only
  exec { 'configure_ik_llama_cpp':
    command => '/usr/bin/cmake -B /opt/ik_llama.cpp/build -DGGML_CUDA=OFF -DGGML_BLAS=OFF -DCMAKE_BUILD_TYPE=Release',
    cwd     => '/opt/ik_llama.cpp',
    creates => '/opt/ik_llama.cpp/build/CMakeCache.txt',
    require => [Exec['clone_ik_llama_cpp'], Package['cmake']],
    path    => ['/usr/bin', '/bin'],
    timeout => 300,  # 5 minutes timeout
  }
  
  # Build ik_llama.cpp
  exec { 'build_ik_llama_cpp':
    command => '/usr/bin/cmake --build /opt/ik_llama.cpp/build --config Release -j $(nproc)',
    require => Exec['configure_ik_llama_cpp'],
    path    => ['/usr/bin', '/bin'],
    timeout => 1800,  # 30 minutes timeout for build
  }
  
  # Create symbolic links for common binaries in /usr/local/bin
  file { '/usr/local/bin/llama-server':
    ensure => link,
    target => '/opt/ik_llama.cpp/build/bin/llama-server',
    require => Exec['build_ik_llama_cpp'],
  }
  
  file { '/usr/local/bin/llama-cli':
    ensure => link,
    target => '/opt/ik_llama.cpp/build/bin/llama-cli',
    require => Exec['build_ik_llama_cpp'],
  }
  
  file { '/usr/local/bin/llama-embedding':
    ensure => link,
    target => '/opt/ik_llama.cpp/build/bin/llama-embedding',
    require => Exec['build_ik_llama_cpp'],
  }
  
  file { '/usr/local/bin/llama-bench':
    ensure => link,
    target => '/opt/ik_llama.cpp/build/bin/llama-bench',
    require => Exec['build_ik_llama_cpp'],
  }
  
  # Create ik_llama.cpp environment configuration script
  file { '/etc/profile.d/ik_llama_cpp.sh':
    ensure  => file,
    content => @(EOT)
# ik_llama.cpp Configuration
export IK_LLAMA_CPP_ROOT="/opt/ik_llama.cpp"
export IK_LLAMA_CPP_BIN="${IK_LLAMA_CPP_ROOT}/build/bin"
export PATH="${IK_LLAMA_CPP_BIN}:$PATH"

# CPU-only inference settings
export GGML_CUDA=OFF
export GGML_BLAS=OFF
|| EOT
    mode    => '0644',
    require => Exec['build_ik_llama_cpp'],
  }
  
  # Create activation script for easy use
  file { '/usr/local/bin/ik-llama-activate':
    ensure  => file,
    content => @(EOT)
#!/bin/bash
# Activate ik_llama.cpp environment
source /etc/profile.d/ik_llama_cpp.sh
echo "ik_llama.cpp environment activated!"
echo "Binaries available in: ${IK_LLAMA_CPP_BIN}"
echo "Available commands: llama-server, llama-cli, llama-embedding, llama-bench"
echo ""
echo "Example usage:"
echo "  llama-server -m <model-path> --host 0.0.0.0 --port 8080"
echo "  llama-cli -m <model-path> -p \"Your prompt here\""
|| EOT
    mode    => '0755',
    require => File['/etc/profile.d/ik_llama_cpp.sh'],
  }
  
  # Verify installation
  exec { 'verify_ik_llama_cpp_installation':
    command => '/opt/ik_llama.cpp/build/bin/llama-server --version',
    require => File['/etc/profile.d/ik_llama_cpp.sh'],
    path    => ['/opt/ik_llama.cpp/build/bin', '/usr/bin', '/bin'],
    logoutput => true,
  }
}

# Apply the class
include ik_llama_cpp

