defmodule CursorDocs.AI.Hardware do
  @moduledoc """
  Hardware detection and capability assessment.

  Detects available compute resources:
  - CPUs (cores, threads, AVX support)
  - NVIDIA GPUs (CUDA)
  - AMD GPUs (ROCm)
  - Intel GPUs (OneAPI/SYCL)
  - Apple Silicon (Metal)
  - ARM devices (NEON)

  ## Usage

      # Get full hardware profile
      profile = Hardware.detect()

      # Check specific capabilities
      Hardware.has_gpu?()
      Hardware.has_cuda?()
      Hardware.recommended_backend()

  ## Resource Scheduling

  The hardware profile is used to:
  - Select appropriate embedding models
  - Set batch sizes
  - Avoid overwhelming the system
  - Enable/disable features based on capability
  """

  require Logger

  @type gpu_info :: %{
    vendor: :nvidia | :amd | :intel | :apple | :unknown,
    name: String.t(),
    vram_mb: non_neg_integer(),
    compute_capability: String.t() | nil,
    driver_version: String.t() | nil
  }

  @type hardware_profile :: %{
    cpu: %{
      cores: pos_integer(),
      threads: pos_integer(),
      model: String.t(),
      avx: boolean(),
      avx2: boolean(),
      avx512: boolean()
    },
    ram_mb: non_neg_integer(),
    gpus: list(gpu_info()),
    platform: :linux | :macos | :windows | :unknown,
    arch: :x86_64 | :aarch64 | :arm | :unknown
  }

  @doc """
  Detect hardware capabilities.
  Results are cached for the session.
  """
  @spec detect() :: hardware_profile()
  def detect do
    case :persistent_term.get({__MODULE__, :profile}, nil) do
      nil ->
        profile = do_detect()
        :persistent_term.put({__MODULE__, :profile}, profile)
        profile

      profile ->
        profile
    end
  end

  @doc """
  Force re-detection of hardware.
  """
  def refresh do
    :persistent_term.erase({__MODULE__, :profile})
    detect()
  end

  @doc """
  Check if any GPU is available.
  """
  def has_gpu? do
    length(detect().gpus) > 0
  end

  @doc """
  Check if NVIDIA CUDA is available.
  """
  def has_cuda? do
    Enum.any?(detect().gpus, &(&1.vendor == :nvidia))
  end

  @doc """
  Check if AMD ROCm is available.
  """
  def has_rocm? do
    Enum.any?(detect().gpus, &(&1.vendor == :amd))
  end

  @doc """
  Check if Intel GPU is available.
  """
  def has_intel_gpu? do
    Enum.any?(detect().gpus, &(&1.vendor == :intel))
  end

  @doc """
  Get total GPU VRAM in MB.
  """
  def total_vram_mb do
    detect().gpus
    |> Enum.map(& &1.vram_mb)
    |> Enum.sum()
  end

  @doc """
  Get recommended inference backend based on hardware.
  """
  def recommended_backend do
    profile = detect()

    cond do
      has_cuda?() -> :cuda
      has_rocm?() -> :rocm
      has_intel_gpu?() -> :sycl
      profile.arch == :aarch64 -> :cpu_neon
      profile.cpu.avx2 -> :cpu_avx2
      true -> :cpu
    end
  end

  @doc """
  Get recommended batch size for embeddings.
  """
  def recommended_batch_size do
    profile = detect()

    cond do
      total_vram_mb() > 8000 -> 32
      total_vram_mb() > 4000 -> 16
      total_vram_mb() > 2000 -> 8
      profile.ram_mb > 16000 -> 8
      profile.ram_mb > 8000 -> 4
      true -> 2
    end
  end

  @doc """
  Get recommended embedding model based on hardware.
  """
  def recommended_model do
    cond do
      total_vram_mb() > 8000 -> "nomic-embed-text"
      total_vram_mb() > 4000 -> "all-minilm"
      has_gpu?() -> "all-minilm"
      true -> "all-minilm"  # Smaller model for CPU
    end
  end

  @doc """
  Check if system can run embeddings without impacting user.
  """
  def can_run_background_embeddings? do
    profile = detect()

    # Heuristics for "won't slow down the PC"
    has_gpu?() or
    (profile.cpu.threads >= 8 and profile.ram_mb > 16000) or
    (profile.cpu.threads >= 4 and profile.ram_mb > 8000 and profile.cpu.avx2)
  end

  @doc """
  Get a human-readable summary of hardware.
  """
  def summary do
    profile = detect()

    gpu_summary = case profile.gpus do
      [] -> "No GPU"
      gpus ->
        gpus
        |> Enum.map(fn gpu -> "#{gpu.name} (#{div(gpu.vram_mb, 1024)}GB)" end)
        |> Enum.join(", ")
    end

    """
    Hardware Profile:
      CPU: #{profile.cpu.model} (#{profile.cpu.threads} threads)
      RAM: #{div(profile.ram_mb, 1024)}GB
      GPU: #{gpu_summary}
      Backend: #{recommended_backend()}
      Batch Size: #{recommended_batch_size()}
      Model: #{recommended_model()}
      Background OK: #{can_run_background_embeddings?()}
    """
  end

  # ============================================================================
  # Detection Implementation
  # ============================================================================

  defp do_detect do
    %{
      cpu: detect_cpu(),
      ram_mb: detect_ram(),
      gpus: detect_gpus(),
      platform: detect_platform(),
      arch: detect_arch()
    }
  end

  defp detect_cpu do
    # Try to get CPU info from /proc/cpuinfo on Linux
    cpu_info = case File.read("/proc/cpuinfo") do
      {:ok, content} -> parse_cpuinfo(content)
      _ -> %{}
    end

    # Get core count
    cores = :erlang.system_info(:logical_processors_available)
    threads = :erlang.system_info(:schedulers_online)

    %{
      cores: cores,
      threads: threads,
      model: cpu_info[:model] || "Unknown",
      avx: cpu_info[:avx] || false,
      avx2: cpu_info[:avx2] || false,
      avx512: cpu_info[:avx512] || false
    }
  end

  defp parse_cpuinfo(content) do
    lines = String.split(content, "\n")

    model = lines
    |> Enum.find(&String.starts_with?(&1, "model name"))
    |> case do
      nil -> "Unknown"
      line -> line |> String.split(":") |> List.last() |> String.trim()
    end

    flags = lines
    |> Enum.find(&String.starts_with?(&1, "flags"))
    |> case do
      nil -> ""
      line -> line |> String.split(":") |> List.last() |> String.trim()
    end

    %{
      model: model,
      avx: String.contains?(flags, "avx ") or String.contains?(flags, "avx\n"),
      avx2: String.contains?(flags, "avx2"),
      avx512: String.contains?(flags, "avx512")
    }
  end

  defp detect_ram do
    case File.read("/proc/meminfo") do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.find(&String.starts_with?(&1, "MemTotal:"))
        |> case do
          nil -> 0
          line ->
            line
            |> String.replace(~r/[^\d]/, "")
            |> String.to_integer()
            |> div(1024)  # Convert KB to MB
        end

      _ ->
        # Fallback: estimate from Erlang
        :erlang.memory(:total) |> div(1024 * 1024)
    end
  end

  defp detect_gpus do
    nvidia_gpus = detect_nvidia_gpus()
    intel_gpus = detect_intel_gpus()
    amd_gpus = detect_amd_gpus()

    nvidia_gpus ++ intel_gpus ++ amd_gpus
  end

  defp detect_nvidia_gpus do
    case System.cmd("nvidia-smi", ["--query-gpu=name,memory.total,driver_version", "--format=csv,noheader,nounits"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.trim()
        |> String.split("\n")
        |> Enum.map(fn line ->
          case String.split(line, ", ") do
            [name, vram, driver] ->
              %{
                vendor: :nvidia,
                name: String.trim(name),
                vram_mb: parse_int(vram),
                compute_capability: nil,
                driver_version: String.trim(driver)
              }
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp detect_intel_gpus do
    # Check for Intel GPU via sysfs
    case File.ls("/sys/class/drm") do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.starts_with?(&1, "card"))
        |> Enum.filter(fn card ->
          vendor_path = "/sys/class/drm/#{card}/device/vendor"
          case File.read(vendor_path) do
            {:ok, content} -> String.contains?(content, "8086")  # Intel vendor ID
            _ -> false
          end
        end)
        |> Enum.take(1)  # Only report one Intel GPU entry
        |> Enum.map(fn _card ->
          # Try to get GPU name from device info
          name = case System.cmd("lspci", ["-nn"], stderr_to_stdout: true) do
            {output, 0} ->
              output
              |> String.split("\n")
              |> Enum.find(fn line ->
                String.contains?(line, "VGA") and String.contains?(line, "8086:")
              end)
              |> case do
                nil -> "Intel GPU"
                line ->
                  # Extract the GPU name from lspci output
                  # Format: "03:00.0 VGA compatible controller [0300]: Intel Corporation DG2 [Arc A770] [8086:56a0] (rev 08)"
                  cond do
                    String.contains?(line, "Arc A770") or String.contains?(line, "56a0") -> "Intel Arc A770"
                    String.contains?(line, "Arc A750") or String.contains?(line, "56a1") -> "Intel Arc A750"
                    String.contains?(line, "Arc A580") or String.contains?(line, "56a5") -> "Intel Arc A580"
                    String.contains?(line, "Arc A380") or String.contains?(line, "56a6") -> "Intel Arc A380"
                    String.contains?(line, "Arc") -> "Intel Arc"
                    String.contains?(line, "Iris") -> "Intel Iris"
                    String.contains?(line, "UHD") -> "Intel UHD"
                    true -> "Intel GPU"
                  end
              end
            _ -> "Intel GPU"
          end

          # Estimate VRAM
          vram = estimate_intel_vram(name)

          %{
            vendor: :intel,
            name: name,
            vram_mb: vram,
            compute_capability: nil,
            driver_version: nil
          }
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp estimate_intel_vram(name) when is_binary(name) do
    # Intel Arc GPUs have dedicated VRAM
    # For integrated, estimate ~25% of system RAM up to 4GB
    cond do
      String.contains?(name, "A770") -> 16384
      String.contains?(name, "A750") -> 8192
      String.contains?(name, "A580") -> 8192
      String.contains?(name, "A380") -> 6144
      String.contains?(name, "Arc") -> 8192  # Default Arc
      true -> min(div(detect_ram(), 4), 4096)  # Integrated
    end
  end
  defp estimate_intel_vram(_), do: 2048

  defp detect_amd_gpus do
    case System.cmd("rocm-smi", ["--showmeminfo", "vram"], stderr_to_stdout: true) do
      {output, 0} ->
        # Parse rocm-smi output
        [%{
          vendor: :amd,
          name: "AMD GPU",
          vram_mb: parse_rocm_vram(output),
          compute_capability: nil,
          driver_version: nil
        }]
      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp parse_rocm_vram(output) do
    # Extract VRAM from rocm-smi output
    output
    |> String.split("\n")
    |> Enum.find(&String.contains?(&1, "Total"))
    |> case do
      nil -> 0
      line ->
        line
        |> String.replace(~r/[^\d]/, "")
        |> parse_int()
        |> div(1024 * 1024)  # Bytes to MB
    end
  end

  defp detect_platform do
    case :os.type() do
      {:unix, :linux} -> :linux
      {:unix, :darwin} -> :macos
      {:win32, _} -> :windows
      _ -> :unknown
    end
  end

  defp detect_arch do
    case :erlang.system_info(:system_architecture) |> to_string() do
      "x86_64" <> _ -> :x86_64
      "aarch64" <> _ -> :aarch64
      "arm" <> _ -> :arm
      _ -> :unknown
    end
  end

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(String.trim(str)) do
      {n, _} -> n
      :error -> 0
    end
  end
  defp parse_int(_), do: 0
end
