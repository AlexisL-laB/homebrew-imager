# frozen_string_literal: true

class Imager < Formula
  #--------------
  # Fonctions
  #--------------

  # Convert version from mmmYY to YYYYmm
  #
  # input: mmmYY (ex: nov25)
  # output: YYYYMM (ex: 202511)
  def self.convert_version(my_version)
    month_str = my_version[0..2]
    year_str  = my_version[3..4]

    month_number = {
      "jan" => "01", "feb" => "02", "mar" => "03", "apr" => "04",
      "may" => "05", "jun" => "06", "jul" => "07", "aug" => "08",
      "sep" => "09", "oct" => "10", "nov" => "11", "dec" => "12"
    }[month_str.downcase]

    raise "Invalid month name: #{month_str}" unless month_number

    "20#{year_str}#{month_number}"
  end

  # Convert version from mmmYY to Mmm-YYYY
  #
  # input: mmmYY (ex: nov25)
  # output: Mmm-YYYY (ex: Nov-2025)
  def convert_version_for_test(my_version)
    month_str = my_version[0..2].capitalize  # "Nov"
    year_str  = my_version[3..4]             # "25"

    "#{month_str}-20#{year_str}"
  end

  # Find architecture (arm64, x86_64)
  def arch_name
    Hardware::CPU.arm? ? "arm64" : "x86_64"
  end

  # Find OS (macos, linux)
  def osname
    OS.mac? ? "macos" : "linux"
  end

  # Check the full build architecture directory structure
  # output: arch-name-fortran (ex: x86_64-ubuntu24.04-gfortran)
  def detect_build_system(mypath, arch = nil, fortran = nil)
    # Valeurs par défaut si non précisées
    arch ||= Hardware::CPU.arm? ? "arm64" : "x86_64"
    fortran ||= File.basename(ENV["FC"] || "gfortran").downcase # nom sans le chemin
    
    # Détecter si gfortran
    # peut être /home/linuxbrew/.linuxbrew/opt/gcc/bin/gfortran-15, gfotran-15, gfortran...
    if fortran&.include?("gfortran")
      fortran = "gfortran"
    end

    odie "Directory does not exist: #{mypath}" unless mypath.directory?

    # Liste tous les sous-répertoires
    systems = mypath.children.select(&:directory?)

    # Filtrer par architecture et compilateur
    matches = systems.select do |d|
      name = d.basename.to_s
      name.start_with?("#{arch}-") && name.end_with?("-#{fortran}")
    end

    # Vérifications
    odie "No matching build directory found in #{mypath}" if matches.empty?
    odie "Multiple matching build directories found: #{matches.map(&:basename)}" if matches.size > 1

    built_dir = matches.first
    # ohai "Detected build system: #{built_dir.basename}"

    # Retourne arch-basename-fortran
    built_dir.basename.to_s
  end

  # Installation du wrapper 'name' dans le répertoire bin
  # Basé sur les modèles fournis (imager.in, viewer.in) disponibles 
  # dans le répertoire Formula/files/ (Homebrew/Library/Taps/lab/homebrew-imager/)
  def install_wrapper(name)
    ohai "Installing wrapper..."
    ohai "*** #{name} ***"

    # Chemin vers le template (répertoire Formula/files/)
    formula_files = File.expand_path("files", __dir__)
    in_file = Pathname.new(formula_files)/"#{name}.in" # recherche du fichier .in
    return unless in_file.exist?

    # Variables d'environnement spécifiques Imager
    gag_root_dir = libexec/"imager-exe-#{MY_VERSION}"
    
    ohai "Buildpath tree (LIBEXEC):"
    system "find", libexec.to_s, "-maxdepth", "3", "-type", "d"

    ohai "Buildpath tree (BUILD):"
    system "find", buildpath.to_s, "-maxdepth", "3", "-type", "d"
    
    gag_exec_system = detect_build_system(gag_root_dir, arch_name.to_s, ENV["FC"])
    # return, for example, x86_64-ubuntu24.04-gfortran

    content = File.read(in_file)
                  .gsub("@PREFIX@/lib/imager", gag_root_dir.to_s)
                  .gsub("@ARCH@-@OSNAME@-gfortran", gag_exec_system)
                  .gsub("DYLD_", "LD_")

    wrapper = buildpath/"#{name}.wrapper"
    wrapper.write content

    bin.install wrapper => name
    chmod 0755, bin/name

    ohai "End"
  end

  #--------------
  # Paramètres
  #--------------

  #####################
  # TO UPDATE #########
  MY_VERSION = "nov26"
  # Source version comment
  # source_version = "4.6-03"
  #####################
  VERSION = convert_version(MY_VERSION).freeze

  #--------------
  # Metadata
  #--------------

  desc "Radio-interferometry data analysis software"
  homepage "https://imager.oasu.u-bordeaux.fr"
  url "https://share.oasu.u-bordeaux.fr/imager/imager-#{MY_VERSION}.tar.xz"
  version VERSION

  #####################
  # TO UPDATE #########
  sha256 "7f58c469074617e6b79e041f94bd944302ffb7669c43e81034992d4d026ad1f9"
  #####################

  license "MIT" # TODO: Update licence ; BSD-3-Clause ? MIT ?

  # Check new version?
  livecheck do
    skip "Upstream versions use a non-numeric month-based scheme (e.g. nov26)"
  end

  #--------------
  # Dependances
  #--------------

  # Build tools
  depends_on "coreutils" => :build # GNU File, Shell, and Text utilities
  depends_on "gcc@15" => :build # GNU C Compiler
  depends_on "groff" => :build # GNU troff text-formatting system
  depends_on "pkgconf" => :build # Package compiler and linker metadata toolkit

  # Runtime libraries
  depends_on "cfitsio" # Manipulation de fichiers FITS
  depends_on "fftw" # Transformés de Fourier discrètes
  depends_on "gdk-pixbuf" # Chargement et manipulation d'images pour gtk2
  depends_on "gtk+3" # Interface graphique GTK2
  depends_on "harfbuzz" # Rendu de polices vectorielles
  depends_on "libpng" # Manipulation de fichiers png

  # Python stack
  depends_on "numpy"
  depends_on "python-setuptools"
  depends_on "python@3.13"


  #--------------
  # Installation
  #--------------

  def install
    # Add GNU coreutils and Python to PATH
    ENV.prepend_path "PATH", Formula["coreutils"].opt_libexec/"gnubin"
    ENV.prepend_path "PATH", Formula["python@3.13"].opt_bin
    
    # Compilers and flags
    gcc = Formula["gcc@15"]
    ENV["CC"]  = gcc.opt_bin/"gcc-15"
    ENV["CXX"] = gcc.opt_bin/"g++-15"
    ENV["CPP"] = "#{ENV["CXX"]} -E -cpp"
    ENV["FC"]  = gcc.opt_bin/"gfortran-15"

    gfortran_lib = gcc.opt_prefix/"lib" # gcc-15 libs path
    # gcc.opt_prefix = /home/linuxbrew/.linuxbrew/opt/gcc@15 (Linux)
    # ou = /opt/homebrew/opt/gcc@15 (macOS)
    ENV.append "CPPFLAGS", "-L#{gcc.opt_lib} -L#{gfortran_lib}"
    ENV.append "LDFLAGS",  "-L#{gcc.opt_lib} -L#{gfortran_lib}"

    # -----------------------------
    # Configure files
    # -----------------------------
    adminsrc_dir = buildpath
    # return unless adminsrc_dir.directory?

    # Dir.chdir(adminsrc_dir) do
    #   system "bash", "-c", "source substitute.compile.sh"
    #   # NOTE: substitute variables for compilation
    # end

    # -----------------------------
    # Build & install
    # -----------------------------
    system "bash", "-c", <<~EOS
      cd imager-src-#{MY_VERSION} &&
      source admin/gildas-env.sh -o openmp &&
      make -j#{ENV.make_jobs} &&
      make install
    EOS

    # DEBUG
    # Check treepath after installation
    # ohai "Buildpath tree:"
    # system "find", buildpath.to_s, "-maxdepth", "4", "-type", "d"

    # -----------------------------
    # Prepare destination directory
    # -----------------------------
    ohai "BUILDPATH=#{buildpath}"
    built_dir = buildpath/"integ"
    ohai "BUILT_DIR=#{built_dir}"
    # Should be like:
    # /var/tmp/imager-[...]/imager-src-nov25/integ

    odie "Build directory does not exist: #{built_dir}" unless built_dir.directory?

    libexec.install built_dir => "imager-exe-#{MY_VERSION}"
    # NOTE: Le dossier de sortie sera renommé "imager-exe-#{MY_VERSION}"
    # et tout ce qui est dans built_dir/ y sera copié

    # Installation des wrappers imager et viewer
    install_wrapper("imager")
    install_wrapper("viewer")
    install_wrapper("class")

    # DEBUG
    # List of installed files
    # ohai "Installed files:"
    # ohai "bin: #{Dir[bin/'*'].join(', ')}"
    # ohai "libexec: #{Dir[libexec/'**/*'].join(', ')}"
  end

  # -----------------
  # Test
  # -----------------
  test do
    # Vérifie que le binaire imager existe et s'exécute
    assert_path_exists bin/"imager"
    assert_predicate bin/"imager", :executable?

    # DEBUG
    # ohai "Contents of libexec/imager-exe-#{MY_VERSION}:"
    # puts (libexec/"imager-exe-#{MY_VERSION}").children.map(&:basename)

    output = shell_output("#{bin}/imager -v 2>&1")
    puts output

    # Vérifie que la sortie contient l'année et l'architecture
    assert_match convert_version_for_test(MY_VERSION.to_s), output

    gag_root_dir = libexec/"imager-exe-#{MY_VERSION}"
    build_system = detect_build_system(gag_root_dir, arch_name.to_s, ENV["FC"])
    # NOTE: ENV["FC"] est vide car test do s’exécute dans un environnement isolé
    assert_match build_system, output
    ohai "All tests passed successfully"
  end
end
