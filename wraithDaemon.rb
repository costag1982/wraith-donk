require 'sinatra'
require 'wraith'
require 'yaml'
require 'json'
require File.join(File.dirname(__FILE__), '/lib/notifications.rb')
require File.join(File.dirname(__FILE__), '/lib/wraith_runner.rb')

if File.exists? 'configs/daemon.yaml'
  daemon_config = YAML::load(File.open('configs/daemon.yaml'))
  set :port, daemon_config['port']
  set :bind, daemon_config['listen']
end

get '/:config' do

  config = params[:config]

  build_history_file = "#{config}.builds.json";
  unless File.exists? build_history_file
    File.open(build_history_file, 'w') { |file| file.write('{"builds":[]}') }
    FileUtils.rm_rf("public/history/#{config}")
  end
  builds = JSON.parse(File.read(build_history_file))

  build_label = 0;
  if params.include? 'label'
    build_label = params['label']
  end

  unless File.exist? "configs/#{config}.yaml"
    return 'Configuration does not exist'
  end

  run_config = YAML::load(File.open("configs/#{config}.yaml"))
  report_location = run_config['wraith_daemon']['report_location']

  pid_file = File.expand_path('wraith.pid', File.dirname(__FILE__));

  if File.exist? pid_file
    return 'Work already in progress, check the gallery for results'
  end

  pid = fork do
    File.open(pid_file, 'w') { |file| file.write("") }

    runner = WraithRunner.new(config, build_label)
    runner.run_wraith
    builds["builds"].push(build_label)
    File.open(build_history_file, 'w') { |file| file.write(builds.to_json) }

    File.delete pid_file

    if runner.has_differences?
      puts 'Some difference spotted, will send notifications'
      notifier = Notifications.new(config, build_label)
      notifier.send
    else
      puts 'No difference spotted, will not send notifications'
    end


    if builds['builds'].length > 10
      (builds['builds'].length-10).times {
        puts "public/history/#{config}/#{builds['builds'][0]}"
        FileUtils.rm_rf "public/history/#{config}/#{builds['builds'][0]}"
        builds['builds'].shift
      }
    end
    File.open(build_history_file, 'w') { |file| file.write(builds.to_json) }

  end

  File.open(pid_file, 'w') { |file| file.write("#{pid}") }
  "Started process pid: #{pid}"

end
