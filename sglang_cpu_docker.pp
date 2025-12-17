# Puppet manifest to setup SGLang with CPU-only support inside Docker
# Usage: puppet apply sglang_cpu_docker.pp

class sglang_cpu_docker (
  String $image_name      = 'sglang-cpu',
  String $container_name  = 'sglang-cpu-server',
  String $model_path      = 'meta-llama/Llama-3.2-1B-Instruct',
  String $host_port       = '30000',
  String $hf_token        = '',
  String $dockerfile_dir  = '/opt/sglang-docker',
) {

  # Ensure Docker is installed
  package { 'docker.io':
    ensure => installed,
  }

  # Ensure Docker service is running
  service { 'docker':
    ensure  => running,
    enable  => true,
    require => Package['docker.io'],
  }

  # Create directory for Dockerfile
  file { $dockerfile_dir:
    ensure => directory,
    mode   => '0755',
  }

  # Create the Dockerfile for SGLang CPU
  file { "${dockerfile_dir}/Dockerfile":
    ensure  => file,
    mode    => '0644',
    require => File[$dockerfile_dir],
    content => @(DOCKERFILE/)
      FROM ubuntu:22.04

      ENV DEBIAN_FRONTEND=noninteractive
      ENV TZ=UTC

      # Install system dependencies
      RUN apt-get update && apt-get install -y \
          git \
          wget \
          curl \
          build-essential \
          cmake \
          libsqlite3-dev \
          libtbb-dev \
          libnuma-dev \
          numactl \
          python3 \
          python3-pip \
          python3-venv \
          && rm -rf /var/lib/apt/lists/*

      # Install Miniconda
      RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh \
          && bash /tmp/miniconda.sh -b -p /opt/miniconda3 \
          && rm /tmp/miniconda.sh

      # Add conda to PATH
      ENV PATH="/opt/miniconda3/bin:${PATH}"

      # Initialize conda and accept TOS
      RUN conda init bash \
          && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true \
          && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true

      # Create conda environment for SGLang CPU
      RUN conda create -n sgl-cpu python=3.12 -y

      # Set up conda environment activation
      SHELL ["/bin/bash", "-c"]

      # Install conda dependencies
      RUN source /opt/miniconda3/bin/activate sgl-cpu \
          && conda install -y libsqlite=3.48.0 gperftools tbb libnuma numactl || true

      # Upgrade pip and install dependencies
      RUN source /opt/miniconda3/bin/activate sgl-cpu \
          && pip install --upgrade pip setuptools \
          && pip install intel-openmp

      # Clone SGLang repository
      RUN git clone https://github.com/sgl-project/sglang.git /opt/sglang

      WORKDIR /opt/sglang

      # Install SGLang with CPU support
      RUN source /opt/miniconda3/bin/activate sgl-cpu \
          && pip install -e "python[all_cpu]"

      # Build CPU backend kernels
      RUN source /opt/miniconda3/bin/activate sgl-cpu \
          && cd /opt/sglang/sgl-kernel \
          && cp pyproject_cpu.toml pyproject.toml \
          && pip install -v .

      # Create environment setup script
      RUN echo '#!/bin/bash' > /entrypoint.sh \
          && echo 'source /opt/miniconda3/bin/activate sgl-cpu' >> /entrypoint.sh \
          && echo 'export CONDA_PREFIX="/opt/miniconda3/envs/sgl-cpu"' >> /entrypoint.sh \
          && echo 'export SGLANG_USE_CPU_ENGINE=1' >> /entrypoint.sh \
          && echo '' >> /entrypoint.sh \
          && echo '# Set up LD_PRELOAD for optimized libraries' >> /entrypoint.sh \
          && echo 'if [ -f "$CONDA_PREFIX/lib/libiomp5.so" ]; then' >> /entrypoint.sh \
          && echo '  export LD_PRELOAD="${LD_PRELOAD}:$CONDA_PREFIX/lib/libiomp5.so"' >> /entrypoint.sh \
          && echo 'fi' >> /entrypoint.sh \
          && echo 'if [ -f "$CONDA_PREFIX/lib/libtcmalloc.so" ]; then' >> /entrypoint.sh \
          && echo '  export LD_PRELOAD="${LD_PRELOAD}:$CONDA_PREFIX/lib/libtcmalloc.so"' >> /entrypoint.sh \
          && echo 'fi' >> /entrypoint.sh \
          && echo 'if [ -f "$CONDA_PREFIX/lib/libtbbmalloc.so.2" ]; then' >> /entrypoint.sh \
          && echo '  export LD_PRELOAD="${LD_PRELOAD}:$CONDA_PREFIX/lib/libtbbmalloc.so.2"' >> /entrypoint.sh \
          && echo 'fi' >> /entrypoint.sh \
          && echo '' >> /entrypoint.sh \
          && echo 'exec "$@"' >> /entrypoint.sh \
          && chmod +x /entrypoint.sh

      # Verify installation
      RUN source /opt/miniconda3/bin/activate sgl-cpu \
          && python -c "import sglang; print('SGLang installed successfully')"

      EXPOSE 30000

      ENTRYPOINT ["/entrypoint.sh"]
      CMD ["python", "-m", "sglang.launch_server", "--model-path", "meta-llama/Llama-3.2-1B-Instruct", "--host", "0.0.0.0", "--port", "30000"]
      | DOCKERFILE
  }

  # Build the Docker image
  exec { 'build_sglang_cpu_image':
    command => "/usr/bin/docker build -t ${image_name} ${dockerfile_dir}",
    unless  => "/usr/bin/docker images -q ${image_name} | /bin/grep -q .",
    require => [
      File["${dockerfile_dir}/Dockerfile"],
      Service['docker'],
    ],
    timeout => 3600,  # 1 hour timeout for build
  }

  # Create Docker volume for model cache
  exec { 'create_sglang_volume':
    command => '/usr/bin/docker volume create sglang-models',
    unless  => '/usr/bin/docker volume inspect sglang-models',
    require => Service['docker'],
  }

  # Build the docker run command based on whether HF token is provided
  $hf_token_env = $hf_token ? {
    ''      => '',
    default => "-e HF_TOKEN=${hf_token}",
  }

  # Create systemd service file for SGLang container
  file { '/etc/systemd/system/sglang-cpu.service':
    ensure  => file,
    mode    => '0644',
    content => @("SYSTEMD"/)
      [Unit]
      Description=SGLang CPU Server Container
      Requires=docker.service
      After=docker.service

      [Service]
      Type=simple
      Restart=always
      RestartSec=10
      ExecStartPre=-/usr/bin/docker stop ${container_name}
      ExecStartPre=-/usr/bin/docker rm ${container_name}
      ExecStart=/usr/bin/docker run --rm --name ${container_name} \
          -p ${host_port}:30000 \
          -v sglang-models:/root/.cache/huggingface \
          ${hf_token_env} \
          ${image_name} \
          python -m sglang.launch_server \
          --model-path ${model_path} \
          --host 0.0.0.0 \
          --port 30000
      ExecStop=/usr/bin/docker stop ${container_name}

      [Install]
      WantedBy=multi-user.target
      | SYSTEMD
    require => Exec['build_sglang_cpu_image'],
    notify  => Exec['systemd_reload'],
  }

  # Reload systemd when service file changes
  exec { 'systemd_reload':
    command     => '/bin/systemctl daemon-reload',
    refreshonly => true,
  }

  # Enable and optionally start the service
  service { 'sglang-cpu':
    ensure  => stopped,  # Set to 'running' to auto-start
    enable  => true,
    require => [
      File['/etc/systemd/system/sglang-cpu.service'],
      Exec['build_sglang_cpu_image'],
      Exec['create_sglang_volume'],
      Exec['systemd_reload'],
    ],
  }

  # Create helper script to manage the container
  file { '/usr/local/bin/sglang-docker':
    ensure  => file,
    mode    => '0755',
    content => @("SCRIPT"/)
      #!/bin/bash
      # SGLang CPU Docker management script

      case "\$1" in
          start)
              echo "Starting SGLang CPU server..."
              systemctl start sglang-cpu
              echo "Server starting on port ${host_port}"
              echo "Check status: sglang-docker status"
              ;;
          stop)
              echo "Stopping SGLang CPU server..."
              systemctl stop sglang-cpu
              ;;
          restart)
              echo "Restarting SGLang CPU server..."
              systemctl restart sglang-cpu
              ;;
          status)
              systemctl status sglang-cpu
              ;;
          logs)
              docker logs -f ${container_name}
              ;;
          shell)
              echo "Starting interactive shell..."
              docker run -it --rm \
                  -v sglang-models:/root/.cache/huggingface \
                  ${image_name} /bin/bash
              ;;
          test)
              echo "Testing SGLang server..."
              curl -s http://localhost:${host_port}/v1/models | python3 -m json.tool
              ;;
          *)
              echo "Usage: \$0 {start|stop|restart|status|logs|shell|test}"
              exit 1
              ;;
      esac
      | SCRIPT
    require => Exec['build_sglang_cpu_image'],
  }

  # Output instructions
  notify { 'sglang_instructions':
    message => "
================================================================================
SGLang CPU Docker Setup Complete!

To manage the server:
  sglang-docker start   - Start the server
  sglang-docker stop    - Stop the server
  sglang-docker status  - Check server status
  sglang-docker logs    - View server logs
  sglang-docker shell   - Open interactive shell
  sglang-docker test    - Test the API

Or use systemctl:
  systemctl start sglang-cpu
  systemctl stop sglang-cpu
  systemctl status sglang-cpu

API endpoint: http://localhost:${host_port}
Model: ${model_path}
================================================================================
",
  }
}

# Apply the class with default parameters
# To customize, use Hiera or pass parameters:
# class { 'sglang_cpu_docker':
#   model_path => 'mistralai/Mistral-7B-Instruct-v0.1',
#   hf_token   => 'hf_xxxxx',
#   host_port  => '8080',
# }
include sglang_cpu_docker
