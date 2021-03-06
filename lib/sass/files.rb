require 'digest/sha1'

module Sass
  # This module contains various bits of functionality
  # related to finding and caching Sass files.
  module Files
    extend self

    def tree_for(filename, options)
      options = Sass::Engine::DEFAULT_OPTIONS.merge(options)
      text = File.read(filename)

      if options[:cache]
        compiled_filename = sassc_filename(filename, options)
        sha = Digest::SHA1.hexdigest(text)

        if root = try_to_read_sassc(filename, compiled_filename, sha)
          root.options = options.merge(:filename => filename)
          return root
        end
      end

      engine = Sass::Engine.new(text, options.merge(:filename => filename))

      begin
        root = engine.to_tree
      rescue Sass::SyntaxError => err
        err.add_backtrace_entry(filename)
        raise err
      end

      try_to_write_sassc(root, compiled_filename, sha, options) if options[:cache]

      root
    end

    def find_file_to_import(filename, load_paths)
      was_sass = false
      original_filename = filename

      if filename[-5..-1] == ".sass"
        filename = filename[0...-5]
        was_sass = true
      elsif filename[-4..-1] == ".css"
        return filename
      end

      new_filename = find_full_path("#{filename}.sass", load_paths)

      return new_filename if new_filename
      return filename + '.css' unless was_sass
      raise SyntaxError.new("File to import not found or unreadable: #{original_filename}.", @line)
    end

    private

    def sassc_filename(filename, options)
      File.join(options[:cache_location],
        Digest::SHA1.hexdigest(File.dirname(File.expand_path(filename))),
        File.basename(filename) + 'c')
    end

    def try_to_read_sassc(filename, compiled_filename, sha)
      return unless File.readable?(compiled_filename)

      File.open(compiled_filename) do |f|
        return unless f.readline("\n").strip == Sass::VERSION
        return unless f.readline("\n").strip == sha
        return Marshal.load(f.read)
      end
    rescue TypeError, ArgumentError => e
      warn "Warning. Error encountered while reading cache #{compiled_filename}: #{e}"
    end

    def try_to_write_sassc(root, compiled_filename, sha, options)
      return unless File.writable?(File.dirname(options[:cache_location]))
      return if File.exists?(options[:cache_location]) && !File.writable?(options[:cache_location])
      return if File.exists?(File.dirname(compiled_filename)) && !File.writable?(File.dirname(compiled_filename))
      return if File.exists?(compiled_filename) && !File.writable?(compiled_filename)
      FileUtils.mkdir_p(File.dirname(compiled_filename))
      File.open(compiled_filename, "w") do |f|
        f.write(Sass::VERSION)
        f.write("\n")
        f.write(sha)
        f.write("\n")
        f.write(Marshal.dump(root))
      end
    end

    def find_full_path(filename, load_paths)
      segments = filename.split(File::SEPARATOR)
      segments.push "_#{segments.pop}"
      partial_name = segments.join(File::SEPARATOR)
      load_paths.each do |path|
        [partial_name, filename].each do |name|
          full_path = File.join(path, name)
          if File.readable?(full_path)
            return full_path
          end
        end
      end
      nil
    end
  end
end
