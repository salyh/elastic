#
#
# this file performs the installation of kibana.
#
# author: Tobias Schaber (codecentric AG)
#
class installkibana {

	# define the path where the puppet files have been checked out from the git repository
	# adjust this for your personal installation.
	$kibanainitlocation 	= '/tmp/elkinstalldir/puppet/files/kibanainit'
	
        # get the url to the kibana installer archive
	$kibanaurl =    hiera('installkibana::kibanaurl')
        $kibana_user =  hiera('installkibana::configkibana::kibana_user', 'kibana')
        $kibana_group = hiera('installkibana::configkibana::kibana_group', 'kibana')

	# create the kibana users group
	group { 'create-kibana-group':
		name => $kibana_group,
		ensure => "present",
	}

	# create the kibana user
	user { 'create-kibana-user':
		name => $kibana_user,
		groups => [$kibana_group],
		ensure => "present",
	} ->

	# download the kibana installer via a wget and save it unter /tmp/...
	wget::fetch { 'download_kibana4':
		source      => $kibanaurl,
		destination => "/tmp/kibana.tar.gz",
		timeout     => 0,
		verbose     => false,
		execuser    => $kibana_user,
	} ->

	# ensure that the kibana4 installation directory exists
	file { "/opt/kibana4":
		ensure => "directory",
		owner => $kibana_user,
		group => $kibana_group,
	} ->
	
	# extract the kibana4 archive into the target installation directory
	exec { "untar-kibana4":	
		command => "tar -xvf /tmp/kibana.tar.gz -C /opt/kibana4 --strip-components=1",
		path => "/bin",
		user => $kibana_user,
  	} ->

	# ensure that a kibana configuration was created and exists now
	file { '/opt/kibana4/config/kibana.yml':
	  ensure => present,
	} ->

	# ensure that the kibana ssl directory exists and has correct rights
	file { '/opt/kibana4/ssl' :
		ensure => "directory",
		owner => $kibana_user,
		group => $kibana_group,
		mode => "0600",
	} ->


	# create the kibana init script. copy it from the checked out git repository
	file { '/etc/init.d/kibana' :
                source => $kibanainitlocation,
		owner => "root",
		group => "root",
		mode => "0755",
	} ->

	# create the kibana default script. copy it from the checked out git repository
	file { '/etc/default/kibana' :
		content => template("/tmp/elkinstalldir/puppet/templates/kibanadefault.erb"),
		owner => "root",
		group => "root",
		mode => "0755",
	} ->


	# set kibana to autostart = true
	exec { 'kibana-service-autostart' :
		command => "chkconfig kibana on",
		path => ["/sbin"],
		user => "root",
	} ->

	# make sure that the kibana service is stopped because it should be started at the end
	service { 'start-kibana' :
		name => "kibana",
		ensure => "stopped",
	} ->

	# perform the configuration steps
	class { 'installkibana::configkibana' : 
	}

	->

	# install the marvel plugin for kibana with a simple shell command
	exec { "install-marvel-kibana-plugin":
		path => ["/usr/local/bin", "/bin", "/usr/bin", "/usr/local/sbin"],
		command => "/opt/kibana4/bin/kibana plugin --install elasticsearch/marvel/latest",
		onlyif => "test ! -d /opt/kibana4/installedPlugins/marvel",
		user => "root",
		cwd => "/opt/kibana4/",
  	} ->

	# install the timelion plugin for kibana with a simple shell command
	exec { "install-timelion-kibana-plugin":
		path => ["/usr/local/bin", "/bin", "/usr/bin", "/usr/local/sbin"],
		command => "/opt/kibana4/bin/kibana plugin --install kibana/timelion",
		onlyif => "test ! -d /opt/kibana4/installedPlugins/timelion",
		user => "root",
		cwd => "/opt/kibana4/",
  	}
}

class installkibana::configkibana(

	$sslsourcescert = '/tmp/elkinstalldir/ssl/kibana.crt',
	$sslsourceskey  = '/tmp/elkinstalldir/ssl/kibana.key',
	$sslcacert      = '/tmp/elkinstalldir/ssl/root-ca.crt',
	$kibanaelkuser  = 'esadmin',
	$kibanaelkpass  = 'esadmin'
) {

	$ownhost = inline_template("<%= scope.lookupvar('::hostname') -%>")

	# the own ip adress of the host (defaults to eth0 ip)
	$address = inline_template("<%= scope.lookupvar('::ipaddress_eth1') -%>")

        $kibana_user = hiera('installkibana::configkibana::kibana_user', 'kibana')
        $kibana_group = hiera('installkibana::configkibana::kibana_group', 'kibana')

	# copy the https ssl key into kibana
	file { '/opt/kibana4/ssl/elkcluster.key' :
		source => $sslsourceskey,
		owner => $kibana_user,
		group => $kibana_group,
		mode => "0600",
	} ->

	# copy the ssl root-ca into kibana
        file { '/opt/kibana4/ssl/root-ca.crt' :
                source => $sslcacert,
		owner => $kibana_user,
		group => $kibana_group,
                mode => "0755",
        } ->

	# copy the https ssl cert into kibana
	file { '/opt/kibana4/ssl/elkcluster.crt' :
		source => $sslsourcescert,
		owner => $kibana_user,
		group => $kibana_group,
	} ->

	# adjust the kibana configuration by setting the correct elasticsearch url.
	# kibana will connect to elasticsearch on its own localhost
	file_line { 'Add es to config.yml':
	  path => '/opt/kibana4/config/kibana.yml', 
	  line => "elasticsearch.url: \"https://${ownhost}:9200\"",
	  match => 'elasticsearch.url:*',
	} ->

	# adjust the kibana configuration by setting the ssl cert path
	# to enable https
	file_line { 'Add https crt to server':
	  path => '/opt/kibana4/config/kibana.yml', 
	  line	 => "server.ssl.cert: /opt/kibana4/ssl/elkcluster.crt",
	  match	=> '#?server.ssl.cert:*',
	} ->

	# adjust the kibana configuration by setting the ssl key path
	# to enable https
	file_line { 'Add https key to server':
	  path => '/opt/kibana4/config/kibana.yml', 
	  line => "server.ssl.key: /opt/kibana4/ssl/elkcluster.key",
	  match	=> '#?server.ssl.key:*',
	} ->

	# adjust the kibana configuration by setting the ssl cert path
        # to enable ssl between kibana and elk
        file_line { 'Add root ca for ssl to server':
          path => '/opt/kibana4/config/kibana.yml',
          line   => "elasticsearch.ssl.ca: /opt/kibana4/ssl/root-ca.crt",
          match => '#?elasticsearch.ssl.ca:*',
        } ->

	# add elasticsearch user to config
	file_line { 'Add elk user to config':
	  path => '/opt/kibana4/config/kibana.yml', 
	  line => "elasticsearch.username: $kibanaelkuser",
	  match	=> '#?elasticsearch.username:*',
	} ->

	# add elasticsearch pass to config
	file_line { 'Add elk pass to config':
	  path => '/opt/kibana4/config/kibana.yml', 
	  line => "elasticsearch.password: $kibanaelkpass",
	  match	=> '#?elasticsearch.password:*',
	}
}



# trigger puppet execution
include installkibana


