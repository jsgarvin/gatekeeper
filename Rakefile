require 'rake'
require 'rake/testtask'
require 'rake/rdoctask'

desc 'Default: run unit tests.'
task :default => :test

desc 'Test the gate_keeper plugin.'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

desc 'Generate documentation for the gate_keeper plugin.'
Rake::RDocTask.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = 'GateKeeper'
  rdoc.options << '--line-numbers' << '--inline-source'
  rdoc.rdoc_files.include('README')
  rdoc.rdoc_files.include('MIT-LICENSE')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

desc 'Measures test coverage using rcov'
task :rcov do
  rm_f "coverage"
  rm_f "coverage.data"
  rcov = "rcov --rails --aggregate coverage.data --text-summary -Ilib"
  system("#{rcov} --html #{Dir.glob('test/**/*_test.rb').join(' ')}")
  if PLATFORM['darwin'] #Mac
    system("open coverage/index.html") 
  elsif PLATFORM[/linux/] #Ubuntu, etc.
    system("/etc/alternatives/x-www-browser coverage/index.html")
  end
end


namespace :rdoc do
  Rake::Task["rdoc"].invoke
  desc 'Publish Rdocs'
  task :publish do
    `scp -r rdoc/* jsgarvin@rubyforge.org:/var/www/gforge-projects/gatekeeper`
  end
end