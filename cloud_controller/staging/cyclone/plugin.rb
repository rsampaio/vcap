class CyclonePlugin < StagingPlugin
  include PipSupport

  REQUIREMENTS = ['twisted']

  def framework
    'cyclone'
  end

  def stage_application
    Dir.chdir(destination_directory) do
      create_app_directories
      copy_source_files
      create_startup_script
      create_twistd_config
    end
  end

  def start_command
    cmds = []
    if uses_pip?
      cmds << install_requirements
    end
    cmds << "twistd -n --pidfile ../run.pid -l ../logs/staging.log -y ../twistd.tac"
    cmds.join("\n")
  end
  
  private
  def startup_script
    vars = environment_hash
    generate_startup_script(vars) do
      setup_python_env(REQUIREMENTS)
    end
  end

  def create_twistd_config
    File.open('twistd.tac', 'w') do |f|
      f.write <<-EOT
import os
import cyclone.web
from twisted.application import service, internet
from cyclone_app import webapp
port = "%s" % os.environ['VCAP_APP_PORT']

application = service.Application("cyclone")
cycloneService = internet.TCPServer(int(port), webapp)
cycloneService.setServiceParent(application)
      EOT
    end
  end

  def generate_startup_script(env_vars = {})
    after_env_before_script = block_given? ? yield : "\n"
    template = <<-SCRIPT
#!/bin/bash
<%= environment_statements_for(env_vars) %>
<%= after_env_before_script %>
<%= change_directory_for_start %>
<%= start_command %> > ../logs/stdout.log 2> ../logs/stderr.log &
sleep 5
STARTED=$(cat $PWD/../run.pid)
echo "#!/bin/bash" >> ../stop
echo "kill -9 $STARTED" >> ../stop
chmod 755 ../stop
wait $STARTED
    SCRIPT
    # TODO - ERB is pretty irritating when it comes to blank lines, such as when 'after_env_before_script' is nil.
    # There is probably a better way that doesn't involve making the above Heredoc horrible.
    ERB.new(template).result(binding).lines.reject {|l| l =~ /^\s*$/}.join
  end

end
