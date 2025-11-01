# SGLang CPU Installation Puppet Manifest

This Puppet manifest (`sglang_cpu.pp`) installs and configures SGLang for CPU inference on a Linux system.

## What it does

1. **Installs system dependencies**: Git, wget, build tools, CMake, and required libraries (libsqlite3, libtbb, libnuma, etc.)
2. **Downloads and installs Miniconda**: Sets up a Python 3.12 environment via Miniconda
3. **Creates a conda environment**: Creates `sgl-cpu` environment specifically for SGLang CPU inference
4. **Clones SGLang repository**: Gets the latest SGLang code from GitHub
5. **Installs dependencies**: Intel OpenMP, gperftools, TBB, and other required packages
6. **Builds SGLang**: Compiles SGLang with CPU backend support
7. **Configures environment**: Sets up environment variables and activation scripts

## Prerequisites

- Puppet installed on the target system
- Root/sudo access
- Internet connection
- At least 10GB free disk space (for conda and compilation)
- Build time: approximately 30-60 minutes depending on system performance

## Usage

### Apply the manifest:

```bash
sudo puppet apply sglang_cpu.pp
```

### Using Puppet agent (if you have a Puppet master):

```bash
sudo puppet agent -t
```

Then add this to your Puppet master's site manifest:
```puppet
node 'your-node-name' {
  include sglang_cpu
}
```

## Post-Installation

After installation, you can activate the SGLang environment using:

```bash
source /etc/profile.d/sglang.sh
```

Or use the convenience script:
```bash
sglang-activate
```

## Verification

Test the installation:
```bash
source /etc/profile.d/sglang.sh
python -c "import sglang; print('SGLang installed successfully')"
```

## Configuration Details

The manifest sets the following:
- **Environment variable**: `SGLANG_USE_CPU_ENGINE=1` - Enables CPU inference mode
- **LD_PRELOAD**: Loads Intel OpenMP, TCMalloc, and TBB memory allocators for optimal CPU performance
- **Conda environment**: Isolated `sgl-cpu` environment with Python 3.12

## Files Created

- `/opt/miniconda3` - Miniconda installation
- `/opt/sglang` - SGLang source code
- `/opt/miniconda3/envs/sgl-cpu` - Conda environment
- `/etc/profile.d/sglang.sh` - Environment configuration
- `/usr/local/bin/sglang-activate` - Activation convenience script

## Troubleshooting

### If installation fails:
1. Check system resources (disk space, memory)
2. Verify internet connectivity
3. Review Puppet logs: `/var/log/puppet/puppet.log`
4. Ensure all system packages are available in your package manager

### To reinstall:
```bash
sudo rm -rf /opt/miniconda3 /opt/sglang
sudo puppet apply sglang_cpu.pp
```

## Notes

- The build process can take 30-60 minutes depending on CPU performance
- The manifest includes timeouts to prevent hanging builds
- All commands run in the isolated `sgl-cpu` conda environment
- The installation is optimized for CPU inference, not GPU
