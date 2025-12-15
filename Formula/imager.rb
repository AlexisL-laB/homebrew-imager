# frozen_string_literal: true

class Imager < Formula
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

  #####################
  # TO UPDATE #########
  MY_VERSION = "nov25"
  # Source version comment
  # source_version = "4.6-03"
  #####################
  VERSION = convert_version(MY_VERSION).freeze

  # Metadata
  desc "Radio-interferometry data analysis software"
  homepage "https://imager.oasu.u-bordeaux.fr"
  url "https://share.oasu.u-bordeaux.fr/imager/imager-#{MY_VERSION}.tgz"
  version VERSION

  #####################
  # TO UPDATE #########
  sha256 "6f89e25d94d7997e76f96becd60724c370456bd54369192cbe8f8c8489227757"
  #####################

  license "MIT" # TODO: Update licence ; BSD-3-Clause ? MIT ?

  # Check new version?
  livecheck do
    skip "Upstream versions use non-numeric month-based scheme (e.g. nov25)"
  end

  # DEPENDANCIES

  # Build tools
  depends_on "coreutils" => :build
  depends_on "gcc@15" => :build
  depends_on "groff" => :build
  depends_on "pkgconf" => :build

  # Runtime libraries
  depends_on "cfitsio"
  depends_on "fftw"
  depends_on "gdk-pixbuf"
  depends_on "gtk+"
  depends_on "harfbuzz"
  depends_on "libpng"

  # Python stack
  depends_on "numpy"
  depends_on "python-setuptools"
  depends_on "python@3.13"

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

  # INSTALLATION
  def install
    # Add GNU coreutils and Python to PATH
    ENV.prepend_path "PATH", Formula["coreutils"].opt_libexec/"gnubin"
    ENV.prepend_path "PATH", Formula["python@3.13"].opt_bin
    
    # Compilers and flags
    ENV["CC"]  = Formula["gcc@15"].opt_bin/"gcc-15"
    ENV["CXX"] = Formula["gcc@15"].opt_bin/"g++-15"
    ENV["CPP"] = "#{Formula["gcc@15"].opt_bin}/g++-15 -E -cpp"
    ENV["FC"]  = "gfortran" # No direct reference to the version (ie not gfortran-15)

    ENV.append "CPPFLAGS", "-L#{Formula["gcc@15"].opt_lib} -lgfortran"
    ENV.append "LDFLAGS",  "-L#{Formula["gcc@15"].opt_lib} -lgfortran"

    # -----------------------------
    # Configure files
    # -----------------------------
    adminsrc_dir = buildpath/"Admin-Source"
    return unless adminsrc_dir.directory?

    Dir.chdir(adminsrc_dir) do
      system "bash", "-c", "source substitute.compile.sh"
      # NOTE: substitute variables (TODO: Check on scratch install)
    end

    # -----------------------------
    # Build & install
    # -----------------------------
    system "bash", "-c", <<~EOS
      source admin/imager-env.sh -o openmp &&
      make --jobs=#{ENV.make_jobs} &&
      make -w install
    EOS

    # Check treepath
    # ohai "Buildpath tree:"
    # system "find", buildpath.to_s, "-maxdepth", "4", "-type", "d"

    # -----------------------------
    # Prepare destination directory
    # -----------------------------
    ohai "BUILDPATH=#{buildpath}"
    built_dir = buildpath/"integ"
    ohai "BUILT_DIR=#{built_dir}"
    # Should be like:
    # BUILT_DIR=/var/tmp/imager-20251214-1952682-tfibrl/imager-src-nov25/integ

    odie "Build directory does not exist: #{built_dir}" unless built_dir.directory?

    libexec.install built_dir => "imager-exe-#{MY_VERSION}"
    # NOTE: Le dossier de sortie est sera renommé "imager-exe-#{MY_VERSION}"
    # et tout ce qui est dans built_dir/ sera copié

    # Installation des wrappers (imager, viewer)
    # Basé sur les modèles fournis (imager.in, viewer.in) disponibles 
    # dans le répertoire Formula/files/ (Homebrew/Library/Taps/lab/homebrew-imager/)
    
    #ohai "Checking wrapper files..."
    #formula_files = File.expand_path("files", __dir__)
    # Lister tous les fichiers *.in
    #wrapper_files = Dir[File.join(formula_files, "*.in")]
    #ohai "Wrapper files found: #{wrapper_files.join(', ')}"

    install_wrapper("imager")
    install_wrapper("viewer")

    # Doc and share
    # Useful?
    #man1.install Dir["docs/*.1"] if Dir.exist?("docs")
    #pkgshare.install "share" if Dir.exist?("share")

    # List of installed files
    # ohai "Installed files:"
    # ohai "bin: #{Dir[bin/'*'].join(', ')}"
    # ohai "libexec: #{Dir[libexec/'**/*'].join(', ')}"
  end

  def install_wrapper(name)
    ohai "Install wrapper... // #{name} //"

    # Chemin vers le fichier template (répertoire Formula/files/)
    formula_files = File.expand_path("files", __dir__)
    in_file = Pathname.new(formula_files)/"#{name}.in"
    return unless in_file.exist?

    # Variables d'environnement spécifiques Imager
    gag_root_dir = libexec/"imager-exe-#{MY_VERSION}"
    # gag_exec_system = "#{arch_name}-#{osname}-gfortran"

    # mydir = prefix + gag_root_dir
    gag_exec_system = detect_build_system(gag_root_dir, arch_name.to_s, ENV["FC"])
    # return, for example, x86_64-ubuntu24.04-gfortra

    content = File.read(in_file)
                  .gsub("@PREFIX@/lib/imager", gag_root_dir.to_s)
                  .gsub("@ARCH@-@OSNAME@-gfortran", gag_exec_system)
                  .gsub("DYLD_", "LD_")

    # Créer le wrapper dans buildpath/"#{name}.wrapper"
    wrapper_path = buildpath/"#{name}.wrapper"
    wrapper_path.write <<~EOS
      #{content}
    EOS

    # Installer le wrapper dans bin/
    bin.install wrapper_path => name
    chmod 0755, bin/name

    ohai "End installation wrapper"
  end

  # Test
  test do
    # Vérifie que le binaire imager existe et s'exécute
    assert_path_exists bin/"imager"
    assert_predicate bin/"imager", :executable?

    # ohai "Contents of libexec/imager-exe-#{MY_VERSION}:"
    # puts (libexec/"imager-exe-#{MY_VERSION}").children.map(&:basename)

    # Exécute la commande imager -v et capture la sortie
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
