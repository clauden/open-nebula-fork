#!/usr/bin/env ruby

ONE_LOCATION=ENV["ONE_LOCATION"]

if !ONE_LOCATION
    puts "ONE_LOCATION not set"
    exit -1
end

$: << ONE_LOCATION+"/lib/ruby"

require 'pp'

require 'one_mad'
require 'open3'


class DM < ONEMad
	
	def initialize
		super(5, 4)
	end
	
	def action_init(args)
		send_message("INIT", "SUCCESS")
		log("KVM Access Driver initialized.")
	end
		
	def action_deploy(args)
		std_action("DEPLOY", "create #{args[3]}", args)
	end
	
	def action_shutdown(args)
		std_action("SHUTDOWN", "shutdown #{args[3]}", args)
	end
	
	def action_cancel(args)
		std_action("CANCEL", "destroy #{args[3]}", args)
	end
	
	def action_checkpoint(args)
        send_message("CHECKPOINT", "FAILURE", args[1], "action not supported for KVM")
	end

	def action_save(args)
		std_action("SAVE", "save #{args[3]} #{args[4]}", args)
	end

	def action_restore(args)
		std_action("RESTORE", "restore #{args[3]}", args)
	end
	
	def action_migrate(args)
		send_message("MIGRATE", "FAILURE", args[1], "action not supported for KVM")
	end
	
	def action_poll(args)
	    
		std=Open3.popen3(
			"ssh -n #{args[2]} virsh dominfo #{args[3]};"+
			" echo ExitCode: $? 1>&2")
		stdout=std[1].read
		stderr=std[2].read
		
		exit_code=get_exit_code(stderr)
		
		if exit_code!=0
			send_message("POLL", "FAILURE", args[1])
			return nil
		end
		
		log("stdout:")
		log(stdout)
		log("stderr:")
		log(stderr)
		
		info = parse_virsh_dominfo(stdout)		

        # TODO -> Get more info, like NET info. Need to know the iface name (e.g. tap0)
						
		send_message("POLL", "SUCCESS", args[1], info)
	end
	
	###########################
	# Common action functions #
	###########################
	
	def std_action(name, command, args)
		std=exec_kvm_command(args[2], command)
		stdout=std[1].read
		stderr=std[2].read
		
		
		
		log("stdout:")
		log(stdout)
		log("stderr:")
		log(stderr)
		
		write_response(name, stdout, stderr, args)
	end
		
	def exec_kvm_command(host, command)
		Open3.popen3(
			"ssh -n #{host} virsh #{command} ;"+
			" echo ExitCode: $? 1>&2")
	end
	
	def write_response(action, stdout, stderr, args)
		exit_code=get_exit_code(stderr)
		
		if exit_code==0
			domain_name=get_domain_name(stdout)
			send_message(action, "SUCCESS", args[1], domain_name)
		else
			error_message=get_error_message(stderr)
			send_message(action, "FAILURE", args[1], error_message)
		end

	end
	

	#########################################
	# Get information from virsh            #
	#########################################

	# From STDERR if exit code == 1
	def get_exit_code(str)
		tmp=str.scan(/^ExitCode: (\d*)$/)
		return nil if !tmp[0]
		tmp[0][0].to_i
	end
	
	# From STDERR if exit code == 1
	def get_error_message(str)
		tmp=str.scan(/^Error: (.*)$/)
		return "Unknown error" if !tmp[0]
		tmp[0][0]
	end

	# From STDOUT if exit code == 0
	def get_domain_name(str)
		tmp=str.scan(/^Domain (.*) created from .*$/)
		return nil if !tmp[0]
		tmp[0][0]
	end
	
	
	###############################
	# Get information from virsh  #
	###############################
		
	
	def parse_virsh_dominfo(returned_info)
	    
	    info = ""
	    
	    returned_info.each_line {|line|
	     
	        columns=line.split(":").collect {|c| c.strip }
	        case columns[0]
                when 'Used memory'
                        info += "USEDMEMORY=" + columns[1].to_i*1024

                end        
	    }    
	
		return info
	end
	
end

dm=DM.new
dm.loop