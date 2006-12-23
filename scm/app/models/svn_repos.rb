require 'rexml/document'

module SvnRepos

  class CommandFailed < StandardError #:nodoc:
  end

  class Base
    @url = nil
    @login = nil
    @password = nil
    
    def initialize(url, login=nil, password=nil)
      @url = url
      @login = login if login && !login.empty?
      @password = (password || "") if @login    
    end
    
    # Returns the entry identified by path and revision identifier
    # or nil if entry doesn't exist in the repository
    def entry(path=nil, identifier=nil)
      path ||= ''
      identifier = 'HEAD' unless identifier and identifier > 0
      entry = nil
      cmd = "svn info --xml -r #{identifier} #{target(path)}"
      IO.popen(cmd) do |io|
        begin
          doc = REXML::Document.new(io)
          doc.elements.each("info/entry") do |info|
            entry = Entry.new({:name => info.attributes['path'],
                           :path => path,
                           :kind => info.attributes['kind'],
                           :lastrev => Revision.new({
                             :identifier => info.elements['commit'].attributes['revision'],
                             :author => info.elements['commit'].elements['author'].text,
                             :time => Time.parse(info.elements['commit'].elements['date'].text)
                             })
                           })
          end
        rescue
        end
      end
      return nil if $? && $?.exitstatus != 0
      entry
    rescue Errno::ENOENT
      raise RepositoryCmdFailed
    end
    
    # Returns an Entries collection
    # or nil if the given path doesn't exist in the repository
    def entries(path=nil, identifier=nil)
      path ||= ''
      identifier = 'HEAD' unless identifier and identifier > 0
      entries = Entries.new
      cmd = "svn list --xml -r #{identifier} #{target(path)}"
      IO.popen(cmd) do |io|
        begin
          doc = REXML::Document.new(io)
          doc.elements.each("lists/list/entry") do |entry|
            entries << Entry.new({:name => entry.elements['name'].text,
                        :path => ((path.empty? ? "" : "#{path}/") + entry.elements['name'].text),
                        :kind => entry.attributes['kind'],
                        :size => (entry.elements['size'] and entry.elements['size'].text).to_i,
                        :lastrev => Revision.new({
                          :identifier => entry.elements['commit'].attributes['revision'],
                          :time => Time.parse(entry.elements['commit'].elements['date'].text),
                          :author => entry.elements['commit'].elements['author'].text
                          })
                        })
          end
        rescue
        end
      end
      return nil if $? && $?.exitstatus != 0
      entries.sort_by_name
    rescue Errno::ENOENT => e
      raise CommandFailed
    end

    def revisions(path=nil, identifier_from=nil, identifier_to=nil, options={})
      path ||= ''
      identifier_from = 'HEAD' unless identifier_from and identifier_from.to_i > 0
      identifier_to = 1 unless identifier_to and identifier_to.to_i > 0
      revisions = []
      cmd = "svn log --xml -r #{identifier_from}:#{identifier_to} "
      cmd << "--verbose " if  options[:with_paths]
      cmd << target(path)
      IO.popen(cmd) do |io|
        begin
          doc = REXML::Document.new(io)
          doc.elements.each("log/logentry") do |logentry|
            paths = []
            logentry.elements.each("paths/path") do |path|
              paths << {:action => path.attributes['action'],
                        :path => path.text
                        }
            end
            revisions << Revision.new({:identifier => logentry.attributes['revision'],
                          :author => logentry.elements['author'].text,
                          :time => Time.parse(logentry.elements['date'].text),
                          :message => logentry.elements['msg'].text,
                          :paths => paths
                        })
          end
        rescue
        end
      end
      return nil if $? && $?.exitstatus != 0
      revisions
    rescue Errno::ENOENT => e
      raise CommandFailed    
    end
    
    def diff(path, identifier_from, identifier_to=nil)
      path ||= ''
      if identifier_to and identifier_to.to_i > 0
        identifier_to = identifier_to.to_i 
      else
        identifier_to = identifier_from.to_i - 1
      end
      cmd = "svn diff -r "
      cmd << "#{identifier_to}:"
      cmd << "#{identifier_from}"
      cmd << target(path)
      diff = []
      IO.popen(cmd) do |io|
        io.each_line do |line|
          diff << line
        end
      end
      return nil if $? && $?.exitstatus != 0
      diff
    rescue Errno::ENOENT => e
      raise CommandFailed    
    end
  
  private
    def target(path)
      " \"" << "#{@url}/#{path}".gsub(/["'<>]/, '') << "\""
    end
  end
  
  class Entries < Array
    def sort_by_name
      sort {|x,y| 
        if x.kind == y.kind
          x.name <=> y.name
        else
          x.kind <=> y.kind
        end
      }   
    end
  end
  
  class Entry
    attr_accessor :name, :path, :kind, :size, :lastrev
    def initialize(attributes={})
      self.name = attributes[:name] if attributes[:name]
      self.path = attributes[:path] if attributes[:path]
      self.kind = attributes[:kind] if attributes[:kind]
      self.size = attributes[:size].to_i if attributes[:size]
      self.lastrev = attributes[:lastrev]
    end
    
    def is_file?
      'file' == self.kind
    end
    
    def is_dir?
      'dir' == self.kind
    end
  end
  
  class Revision
    attr_accessor :identifier, :author, :time, :message, :paths
    def initialize(attributes={})
      self.identifier = attributes[:identifier]
      self.author = attributes[:author]
      self.time = attributes[:time]
      self.message = attributes[:message] || ""
      self.paths = attributes[:paths]
    end
  end
end