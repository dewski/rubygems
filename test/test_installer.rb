#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'fileutils'
require 'tmpdir'
require 'test/unit'
require 'rubygems'
require 'test/gemutilities'
require 'test/io_capture'

Gem::manage_gems

class Gem::Installer
  attr_accessor :options, :directory
end
  
class TestInstaller < RubyGemTestCase
  include Gem::IoCapture

  def setup
    super
    @spec = quick_gem("a")
    @installer = Gem::Installer.new :fake, {}
  end

  def util_gem_dir(version = '0.0.2')
    File.join "gems", "a-#{version}" # HACK
  end

  def util_gem_bindir(version = '0.0.2')
    File.join util_gem_dir(version), "bin"
  end

  def util_inst_bindir
    File.join @gemhome, "bin"
  end

  def util_make_exec(version = '0.0.2')
    @spec.executables = ["my_exec"]
    write_file(File.join(util_gem_bindir(version), "my_exec")) do |f|
      f.puts "#!/bin/ruby"
    end
  end

  def test_generate_bin_scripts
    @installer.options[:wrappers] = true
    util_make_exec

    @installer.generate_bin @spec, @gemhome
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal true, File.exist?(installed_exec)
    assert_equal(0100755, File.stat(installed_exec).mode) unless win_platform?

    wrapper = File.read installed_exec
    assert_match(/generated by RubyGems/, wrapper)
  end

  def test_generate_bin_scripts_no_execs
    @installer.options[:wrappers] = true
    @installer.generate_bin @spec, @gemhome
    assert_equal false, File.exist?(util_inst_bindir)
  end

  def test_generate_bin_scripts_no_perms
    @installer.options[:wrappers] = true
    util_make_exec

    Dir.mkdir util_inst_bindir
    File.chmod 0000, util_inst_bindir

    assert_raises Gem::FilePermissionError do
      @installer.generate_bin @spec, @gemhome
    end

  ensure
    File.chmod 0700, util_inst_bindir unless $DEBUG
  end

  def test_generate_bin_symlinks
    return if win_platform? #Windows FS do not support symlinks
    
    @installer.options[:wrappers] = false
    util_make_exec
    @installer.directory = util_gem_dir

    @installer.generate_bin @spec, @gemhome
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal true, File.symlink?(installed_exec)
    assert_equal(File.join(util_gem_dir, "bin", "my_exec"),
                 File.readlink(installed_exec))
  end

  def test_generate_bin_symlinks_no_execs
    @installer.options[:wrappers] = false
    @installer.generate_bin @spec, @gemhome
    assert_equal false, File.exist?(util_inst_bindir)
  end

  def test_generate_bin_symlinks_no_perms
    @installer.options[:wrappers] = false
    util_make_exec
    @installer.directory = util_gem_dir

    Dir.mkdir util_inst_bindir
    File.chmod 0000, util_inst_bindir

    assert_raises Gem::FilePermissionError do
      @installer.generate_bin @spec, @gemhome
    end

  ensure
    File.chmod 0700, util_inst_bindir unless $DEBUG
  end

  def test_generate_bin_symlinks_update_newer
    return if win_platform? #Windows FS do not support symlinks
    
    @installer.options[:wrappers] = false
    util_make_exec
    @installer.directory = File.join @gemhome, util_gem_dir

    @installer.generate_bin @spec, @gemhome
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal(File.join(@gemhome, util_gem_dir, "bin", "my_exec"),
                 File.readlink(installed_exec))

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "0.0.3"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    util_make_exec '0.0.3'
    @installer.directory = File.join @gemhome, util_gem_dir('0.0.3')
    @installer.generate_bin @spec, @gemhome
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal(File.join(@gemhome, util_gem_dir('0.0.3'), "bin", "my_exec"),
                 File.readlink(installed_exec),
                 "Ensure symlink moved to latest version")
  end

  def test_generate_bin_symlinks_update_older
    return if win_platform? #Windows FS do not support symlinks

    @installer.options[:wrappers] = false
    util_make_exec
    @installer.directory = File.join @gemhome, util_gem_dir

    @installer.generate_bin @spec, @gemhome
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal(File.join(@gemhome, util_gem_dir, "bin", "my_exec"),
                 File.readlink(installed_exec))

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "0.0.1"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    util_make_exec '0.0.1'
    @installer.directory = File.join @gemhome, util_gem_dir('0.0.1')
    @installer.generate_bin @spec, @gemhome
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal(File.join(@gemhome, util_gem_dir('0.0.2'), "bin", "my_exec"),
                 File.readlink(installed_exec),
                 "Ensure symlink not moved")
  end

  def test_generate_bin_symlinks_update_remove_wrapper
    return if win_platform? #Windows FS do not support symlinks

    @installer.options[:wrappers] = true
    util_make_exec
    @installer.directory = util_gem_dir

    @installer.generate_bin @spec, @gemhome
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal true, File.exists?(installed_exec)

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "0.0.3"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    @installer.options[:wrappers] = false
    util_make_exec '0.0.3'
    @installer.directory = util_gem_dir '0.0.3'
    @installer.generate_bin @spec, @gemhome
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal(File.join(util_gem_dir('0.0.3'), "bin", "my_exec"),
                 File.readlink(installed_exec),
                 "Ensure symlink moved to latest version")
  end

  def test_generated_bin_uses_default_shebang
    return if win_platform? #Windows FS do not support symlinks

    @installer.options[:wrappers] = true
    util_make_exec
    @installer.directory = util_gem_dir

    @installer.generate_bin @spec, @gemhome 

    default_shebang = File.join(Config::CONFIG['bindir'], Config::CONFIG['ruby_install_name'])
    shebang_line = open("#{@gemhome}/bin/my_exec") { |f| f.readlines.first }
    assert_match /^#!/, shebang_line
    assert_match /#{default_shebang}/, shebang_line
  end

  def test_generate_bin_symlinks_win32
    old_arch = Config::CONFIG["arch"]
    Config::CONFIG["arch"] = "win32"
    @installer.options[:wrappers] = false
    util_make_exec
    @installer.directory = util_gem_dir

    serr = capture_stderr { 
      @installer.generate_bin @spec, @gemhome
    }
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal true, File.exist?(installed_exec)

    assert_match /unable/i, serr
    assert_match /win32/i, serr
    assert_match /symlinks/i, serr
    assert_match /wrapper/i, serr
    
    expected_mode = win_platform? ? 0100644 : 0100755
    assert_equal expected_mode, File.stat(installed_exec).mode

    wrapper = File.read installed_exec
    assert_match(/generated by RubyGems/, wrapper)
  ensure
    Config::CONFIG["arch"] = old_arch
  end

  def test_install_with_message
    @gem = File.join 'test', 'data', "PostMessage-0.0.1.gem"
    sout = capture_stdout {
      @installer = Gem::Installer.new @gem, {}
      @installer.install
    }
    assert_equal "I am a shiny gem!\n", sout
  end

end
