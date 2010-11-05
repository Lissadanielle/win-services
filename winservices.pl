#!D:\usr\local\Perl\bin\perl
# #############################################################################
# Windows Services Management
# BI AS A SERVICE 
# Tomas Martinez (2010)
#
# see win-services.pl [-h]
# #############################################################################
# $Id$
# $Author$
# $LastChangedDate$
# $Rev$
# -----------------------------------------------------------------------------
use strict;
use Win32::Service;
use Sys::Hostname;
use Time::Local;
use Time::localtime;
use Time::gmtime;
use File::Basename;

my $BY           = 'tomas.martinez@bi-as-service.com';
my $MODUL        = "Windows Services Management";
my $gSVNFile     = '$HeadURL$';
my $gSVNRevision = '$Revision$';
my $gSVNDate     = '$Date$';
my $sLocalHost   = hostname;
$gSVNFile     =~ s/\$//g;
$gSVNRevision =~ s/\$//g;
$gSVNDate     =~ s/\$//g;

# exit 
#  > 0  for success and 1 for error
#
#
# http://www.le-berre.com/perl/perlser.htm
# http://msdn.microsoft.com/en-us/library/default.aspx
my %aWinStatus =
(1 => 'STOPPED',               # The service is not running
 2 => 'START_PENDING',         # The service is starting
 3 => 'STOP_PENDING',          # The service is stopping
 4 => 'RUNNING',               # The service is running
 5 => 'CONTINUE_PENDING',      # The service continue is pending
 6 => 'PAUSE_PENDING',         # The service pause is pending
 7 => 'PAUSED',                # The service is paused
 8 => 'ERROR');

my %aAction = 
(0 => 'STOP',
 1 => 'START',
 2 => 'STATUS');
 
# Define global variables and fixed values ------------------------------------
my $gMaxTimeOut    = 10;
my $gVerbose       = 0;
my $gOnlyConsole   = 0;
my $gAction        = '';
my $gInFile        = '';
my $gOutDir        = '.';
my $gNative        = '';
my $gTotalServices = 0;
my %aSvc;
my %aLength        = (1,1,1,1);
my %aServer        = ();
my %aServerSvc     = ();
my $gTmp       = $ENV{TEMP};
my $HTML_SPACE = "&nbsp;";

# extract just the directory, extension and Filename from a path
my @aSuffixlist = (qr{\.pl},qr{\.exe});
my ($gFileName,$gFilePath,$gFileType) = fileparse(__FILE__,@aSuffixlist);
if ($gFileType ne ".pl") {
  $gNative = "Perl Binary";
} elsif ($gFileType ne ".exe") {   
  $gNative = "Native Perl";
} else {                   
  $gNative = "Unknown Mode";
}


                 
# Set the Null-Device for UNIX or WIN                
my $gNullDevice;
if (isWinOs()) {
  $gNullDevice = "NUL";
} else {
  $gNullDevice = "/dev/null";
}

# ----------------------------------------------------------------------------
# Read value  from command line ----------------------------------------------
my  ($cArg);
while ($_ = $ARGV[0], s/^-(.*)/$1/) {
    shift;
    last if /^-$/;
    while (s/^(.)(.*)/$2/) {
        if ($1 eq 'l') {
            if ($_ ne '') {$cArg=$_;$_=''} else {$cArg=$ARGV[0];shift};
            $gInFile = $cArg;
            next;
        }
        if ($1 eq 'd') {
            if ($_ ne '') {$cArg=$_;$_=''} else {$cArg=$ARGV[0];shift};
            $gOutDir = $cArg;
            die "\n$gOutDir is not a directory : $!\n" if ( (!-e $gOutDir) || (!-d $gOutDir) );
            next;
        }
        if ($1 eq 'a') {
            if ($_ ne '') {$cArg=$_;$_=''} else {$cArg=$ARGV[0];shift};
            $gAction = uc($cArg);
            next;
        }        
        if ($1 eq 't') {
            if ($_ ne '') {$cArg=$_;$_=''} else {$cArg=$ARGV[0];shift};
            $gMaxTimeOut = $cArg;
            next;
        }                
        if ($1 eq 'h' || $1 eq '?') {
            xUsage();
            exit(1);
        }        
        if ($1 eq 'v') {
            $gVerbose = 1;
            next;
        }
        if ($1 eq 'c') {
            $gOnlyConsole = 1;
            next;
        }        
        xUsage();
        warn "Bad option: $1\n";
        exit(1);
    }
}

if ($gInFile eq '') {
    xUsage();   
    warn  "\nIntput File ?\n";
    exit(1);
}
if ($gOutDir eq '') {
    xUsage();
    warn  "\nOutput Directory ?\n";
    exit(1);
}


# Check the Action to be process
if ($gAction eq '') {
   xUsage();
   warn  "\nAction ? \n";
   exit(1);
} else {
  my ($vKey, $vActionFound);
  $vActionFound = 0;
  foreach $vKey (sort keys %aAction) {
    if ($gAction eq "$aAction{$vKey}") {
      $vActionFound++;
    }               
  }     
  if ($vActionFound eq 0) {
   warn  "\nInvalid Action $gAction, use:\n";
   foreach $vKey (sort keys %aAction) {
     warn "\t$aAction{$vKey}\n";
   }            
   exit(1);
  }     
}       





#
# Main Program ---------------------------------------------------------------
#

#
# Print the run information
#
xPrintInfo();

#
# Read the list of service from the input-file
#                       
xAbort("File $gInFile not found")  if (!xVerifyFile($gInFile));
xAbort("Can´t open $gInFile")      if (!open (FILE,$gInFile)); 
my $iId = 0;

printLn("Loading file $gInFile to process $gAction ...");
while (<FILE>) {
  next if (/\s*#/);
  next if (/^\s*$/);
  $gTotalServices++;
  if (/                                        
       \s*'(.+)'\s*  #server:   arbitrary match
       \s*'(.+)'\s*  #service:  arbitrary match
       \s*(\d+)\s*   #sleep:    arbitrary match
       /x) {
       ++$iId;
       xLoadSrv($iId,$1,$2,$3,$gAction);
       $aServer{$1}++;
  }
}
close (FILE) || die "\nCan´t close $gInFile : $!\n";

printLn();
printLn("Count the Services...");
for my $vServerName ( keys %aServer ) {
  my $iCount = $aServer{$vServerName};
  xVerboseLn (sprintf (" > %10s: %d",$vServerName,$iCount));
  my %aServerServices = ();  
  Win32::Service::GetServices($vServerName,\%aServerServices);
  foreach my $vDisplayName (sort keys %aServerServices) {   
    $aServerSvc{$vServerName}{$aServerServices{$vDisplayName}} = $vDisplayName;                                             
    #print "$aServerServices{$vDisplayName} : $vDisplayName\n"; 
  } 
}
                                                       
printLn();
printLn("Processing the services...");
foreach $iId (sort keys %aSvc) {   
  xProcess($iId);
}

printLn();
printLn("Creating Status List...");
foreach $iId (sort keys %aSvc) {   
  xUpdateSrv($iId);
}
my $vStatusFile_Base = $gFileName;
$vStatusFile_Base =~ s/(\w)\.(\w)/$1/;
my $sec  = localtime->sec();
my $min  = localtime->min();
my $hour = localtime->hour();
my $mday = localtime->mday();
my $mon  = localtime->mon() +1;
my $year = localtime->year() + 1900;
if (!$gOnlyConsole) {
  my $vStatusFile_stamp=sprintf("%4.4d%2.2d%2.2d-%2.2d%2.2d%2.2d",$year,$mon,$mday,$hour,$min,$sec);
  xBuildCSVFile($vStatusFile_Base,$vStatusFile_stamp);
}  


exit(0);

# Functions ------------------------------------------------------------------

# Procedure: makeHtmlReport
# Create the HTML report with errors
#
sub xBuildCSVFile() {
  my ($vFileBase,$FileStamp) = @_;
  my $vFileCSV = $gOutDir."\\".$FileStamp."_".$vFileBase.".csv";
  printLn();
  printLn("Writing CSV-File $vFileCSV");
  open (FILE,"> $vFileCSV") || die "\nCan´t open $vFileCSV : $!\n";
  printf FILE ("%s#%s#%s#%s#%s\n","STATUS","SERVER","SERVICE NAME","DISPLAY NAME","MESSAGE");
  foreach $iId (sort keys %aSvc) {
    my $vServer      = $aSvc{$iId}{SERVER};
    my $vServiceName = $aSvc{$iId}{SERVICE};
    my $vStatus      = $aSvc{$iId}{CSTATUS};
    my $vMsg         = $aSvc{$iId}{MSG};
    my $vDisplayName = $aSvc{$iId}{DISPLAY};   
    printf FILE ("%s#%s#%s#%s#%s\n",$vStatus,$vServer,$vServiceName,$vDisplayName,$vMsg);
  }
  close (FILE) || die "\nCan´t close vFileCSV : $!\n";
}

# Function: xUpdateSrv()
# Update the services in the global hash %aSvc
#
sub xUpdateSrv() {
  my ($iId) = @_;
  my $vServer      = $aSvc{$iId}{SERVER};
  my $vServiceName = $aSvc{$iId}{SERVICE};
  my $vMsg         = $aSvc{$iId}{MSG};
  my $vDisplayName = $aServerSvc{$vServer}{$vServiceName}; 
  $aSvc{$iId}{CSTATUS}  = xGetStatus($vServer, $vServiceName);  
  $aSvc{$iId}{DISPLAY}  = $vDisplayName;

  my $iCurStatus   = $aLength{CSTATUS}+2;
  my $iServer      = $aLength{SERVER};
  my $iService     = $aLength{SERVICE};
  my $iDisplayName = $aLength{DISPLAY};
  
  #xVerboseLn(sprintf(" > %-10s %-15s %-10s %-50s %s",$aSvc{$iId}{CSTATUS},$vServer,$vServiceName,$vDisplayName,$vMsg));
  #printf(" > [%-7s] %-15s %-20s %-50s %s\n",$aSvc{$iId}{CSTATUS},$vServer,$vServiceName,$vDisplayName,$vMsg); 
  printf(" > [%-${iCurStatus}s] %-${iServer}s %-${iService}s %-${iDisplayName}s %s\n",
         $aSvc{$iId}{CSTATUS},$vServer,$vServiceName,$vDisplayName,$vMsg);
}

#
# Function: xProcess()
# Saves the services in the global hash %aSvc
#
sub xProcess() {
  my ($iId) = @_;
  my $vDisplayName = $aServerSvc{$aSvc{$iId}{SERVER}}{$aSvc{$iId}{SERVICE}}; 
  my $vCurStatus = $aSvc{$iId}{CSTATUS};
  my $vServer = $aSvc{$iId}{SERVER};
  my $vService = $aSvc{$iId}{SERVICE};
  
  $aLength{CSTATUS}=length($vCurStatus)   if (length($vCurStatus) > $aLength{CSTATUS}   );
  $aLength{SERVER}=length($vServer)       if (length($vServer) > $aLength{SERVER}       );
  $aLength{SERVICE}=length($vService)     if (length($vService) > $aLength{SERVICE}     );
  $aLength{DISPLAY}=length($vDisplayName) if (length($vDisplayName) > $aLength{DISPLAY} );    
    
  xVerboseLn (sprintf (" > [%-7s] %-15s %-20s %s",$vCurStatus,$vServer,$vService,$vDisplayName));

  return if ($aSvc{$iId}{ACTION} eq $aAction{2});   # 2 => 'STATUS'
  if ( $aSvc{$iId}{ACTION} eq $aAction{0} )  {      # 0 => 'STOP'
    my $iCountTimeOut = 0;
    while (xGetStatus($aSvc{$iId}{SERVER},$aSvc{$iId}{SERVICE}) ne "STOPPED") {
      if ($iCountTimeOut++ >  $gMaxTimeOut){
        $aSvc{$iId}{MSG} = "$aSvc{$iId}{ACTION}: Time out ($gMaxTimeOut secs.)";
        last;
      } 
      Win32::Service::StopService($aSvc{$iId}{SERVER},$aSvc{$iId}{SERVICE});
      sleep(1);
    }               
  }
  if ( $aSvc{$iId}{ACTION} eq $aAction{1} )  {      # 1 => 'START'
    my $iCountTimeOut = 0;
    while (xGetStatus($aSvc{$iId}{SERVER},$aSvc{$iId}{SERVICE}) ne "RUNNING") {
      if ($iCountTimeOut++ >  $gMaxTimeOut){
        $aSvc{$iId}{MSG} = "$aSvc{$iId}{ACTION}: Time out ($gMaxTimeOut secs.)";
        last;
      } 
      Win32::Service::StartService($aSvc{$iId}{SERVER},$aSvc{$iId}{SERVICE});
      sleep(1);
    }               
  }


  $aSvc{$iId}{CSTATUS} = xGetStatus($aSvc{$iId}{SERVER},$aSvc{$iId}{SERVICE});      
  xVerboseLn("   + Current Status: $aSvc{$iId}{CSTATUS}");
  xVerboseLn("   + $aSvc{$iId}{MSG}") if ($aSvc{$iId}{MSG} ne '');
  sleep($aSvc{$iId}{sleep});
}

#  if ($vAction eq $aAction{0} {
#    $vTargetStatus =            
#  }    
#my %aAction =   
#(0 => 'STOP',   
# 1 => 'START',  
# 2 => 'STATUS');
        
#
# Function: xLoadSrv()
# Saves the services in the global hash %aSvc
#
sub xLoadSrv() {
  my ($iId,$vServer,$vServiceName,$vSleep, $vAction) = @_;
  $iId = sprintf ("%07d", $iId);
  $aSvc{$iId}{SERVER}   = xTrim($vServer);
  $aSvc{$iId}{SERVICE}  = xTrim($vServiceName);
  $aSvc{$iId}{SLEEP}    = $vSleep;
  $aSvc{$iId}{CSTATUS}  = xGetStatus($vServer, $vServiceName);  
  $aSvc{$iId}{ACTION}   = $vAction;
  $aSvc{$iId}{MSG}      ='';
  xVerboseLn(sprintf("%-10s %-20s %2d",$vServer,$vServiceName,$aSvc{$iId}{SLEEP}));
}

#
# Function: xGetStatus()
# Get the Status
#
sub xGetStatus() {
  my ($vServer,$vServiceName) = @_;
  my (%aServiceState, $iStatus);
  Win32::Service::GetStatus( $vServer,$vServiceName, \%aServiceState);
  $iStatus=$aServiceState{CurrentState};
  #return $iStatus;
  return $aWinStatus{$iStatus};
}       
        
# 
# Function: isWinOs
# return 1 for Windows-OS, otherwise 0
#
sub isWinOs() {
  return ($^O =~/Win/);
}

#
# Perl trim function to remove whitespace from the start and end of the string
#
sub xTrim($) {
  my $string = shift;
  $string =~ s/^\s+//;
  $string =~ s/\s+$//;
  return $string;
}


# 
# Function: xVerbose
#
sub xVerbose() {
  print "@_" if ($gVerbose);
}

# 
# Function: xVerbose
#
sub xVerboseLn() {
  print "@_\n" if ($gVerbose);
}
# 
# Function: xVerbose
#
sub printLn() {
  print "@_\n" 
}

#
# Function: xVerifyFile
# Verify a Txt-File and return 1 (ok) or 0 (error)
#
sub xVerifyFile {
    my ($cFile) =@_;

    if (!-e $cFile) {
        print "\nFile no found '$cFile'\n";
        return(0);
    }
    elsif (-d $cFile) {
        print "\nFile is a directory '$cFile'\n";
        return(0);
    }
    else {
        if (!-T $cFile) {
            print "\nNo text file '$cFile'\n";
            return(0);
        }
        if (-z $cFile) {
            print "\nFile is empty '$cFile'\n";
            return(0);
        }
    }
    return (1);
}

#
# Function: xAbort
# Exit with a message
#
sub xAbort() {
  my ($cMsg) =@_;
  print "\n";
  print " !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! \n";
  print " ABORT WITH ERROR\n";
  print " !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! \n";
  warn "$ cMsg \n";
  exit(1);
}


# Function: xPrintInfo
# Print the run information
#
sub xPrintInfo() {
  print  ("\n");
  print  ("------------------------------------------------------\n");
  printf ("%10s: %s\n","Modul",$MODUL);
  printf ("%10s: %s\n","Powered by",$BY);
  printf ("%10s: %s\n","Version",$gSVNRevision);
  print  ("------------------------------------------------------\n");
  printf ("%15s: %s\n","localhost",$sLocalHost);
  printf ("%15s: %s\n","Run mode",$gNative);
  printf ("%15s: %s\n","Input File",$gInFile);
  printf ("%15s: %s\n","Output Directory",$gOutDir);
  printf ("%15s: %s\n","Action TimeOut",$gMaxTimeOut);
  printf ("%15s: %s\n","Temp-Dir",$gTmp);
  printf ("%15s: %s\n","Verbose Mode",$gVerbose);
  printf ("%15s: %s\n","Console Only",$gOnlyConsole);
  print  ("------------------------------------------------------\n\n");
}

# Function: xUsage
# Print the Help information
#
sub xUsage() {
  print ("\n");
  print ("USAGE: " . $gFileName);
  print (" [-v] [-h] [-c] [-t 15] [-d directory] -l file  -a action\n");
  print ("\t> -v: Verbose Mode \n");
  print ("\t> -h: This help \n");
  print ("\t> -t: Overwrite the defautt timeout (10s.) \n");
  print ("\t> -a: Action to execute [START|STOP|STATUS] \n");
  print ("\t> -c: only console output without csv-Report \n");  
  print ("\t> -l: File with the list of Services in this format: \n");
  print ("\t\t 'Server' 'Service' Sleep after action\n");    
  print ("\t> -d: Output Directory (default current directory) \n");  
  print ("\t\t [.csv] STATUS#SERVER#SERVICE NAME#DISPLAY NAME#MESSAGE\n\n");
  print ("EXAMPLE: " . $gFileName . " -v -l webserver.start -a START");
  print ("\n\n");
}  