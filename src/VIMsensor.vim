 " Vim global plugin for Hackystat sensor
 " Last Change: 2007 July 30
 " Maintainer: Dan Port <dport@hawaii.edu>

 " Description:
 " This file provides support information from inside Vim for use with
 " HSVimSensor.class (an external java process to send Hackystat data
 " for a Vim session).
 " This plugin should be placed in the plugin path (usually 
 " $HOME/.vim/plugin) for a user wishing to send Hackystat data for their 
 " Vim session.
 " 
 " The sensor will not work with multiple Vim sessions that use the same
 " $HOME directory (e.g. multiple users with the same username on the same
 " machine). It is unclear what would happen with different users trying
 " to edit the same file. At present, this does not appear to pose a 
 " problem.

"TBDs:
"
" - check for already running java sensor process
" - invoke only clean, known bash or csh shell
" - staleness timestamping
" - report other interesting Vim events to Vim sensor (only file size changes
"   now)
   
" Use Vim defaults while :source'ing this file.
let save_cpo = &cpo
set cpo&vim

" Define the location of the sensor.properties file here
let s:HSsensorpropfile = $HOME."/.hackystat/v8.sensor.properties"

" Set the appropriate file redirect that can overwrite an existing file
if $SHELL =~ "bash"
        let $redirect_op = " >| "
else
        let $redirect_op = " >! "
endif
  
function s:SPKeyValueForKey(key)
	if !exists('s:sp_str')
		let s:sp_str = system("cat " . s:HSsensorpropfile)
	endif
	return matchstr(s:sp_str, a:key."=[[:graph:]]*")
endfunction
 
function s:ValueForSPKeyValue(keyvalue)
	let start = match(a:keyvalue,"=")
	return strpart(a:keyvalue,start+1,strlen(a:keyvalue)-start)
endfunction   

function s:ValueForKey(key)
	return s:ValueForSPKeyValue( s:SPKeyValueForKey(a:key) )
endfunction

function SetEnvVars(start, ...) 
	let index = 1 
	while (index <= a:0)
		exe 'let s:key = a:'.index  
		exe "let $".s:key . "=\""  . s:ValueForKey(s:key) . '"' 
		let index = index + 1 
	endwhile  
endfunction

" Parse the sensor.properties file if it can be found and set env vars
if filereadable(s:HSsensorpropfile)
	call SetEnvVars(4,"HACKYSTAT_VIM_SENSOR_DATA_FILE","VIM_SWAP_UPDATE_INTERVAL","VIM_SWAP_CHARACTER_UPDATE_INTERVAL", "HACKYSTAT_SENSORSHELL_HOME")
else 
	echo "HS sensor.properties file NOT found"
	finish
endif

let $HACKYSTAT_VIM_SENSOR_DATA_FILE = expand($HACKYSTAT_VIM_SENSOR_DATA_FILE)
if !exists("$HACKYSTAT_VIM_SENSOR_DATA_FILE")
	echo "$HACKYSTAT_VIM_SENSOR_DATA_FILE not defined - using default"
	let $HACKYSTAT_VIM_SENSOR_DATA_FILE = $HOME."/.hackystat/vim/HS_VIM_DATA.dat"
endif

let $HACKYSTAT_SENSORSHELL_HOME = expand($HACKYSTAT_SENSORSHELL_HOME)
if !exists("$HACKYSTAT_SENSORSHELL_HOME")
	echo "$HACKYSTAT_SENSORSHELL_HOME not defined and required! Vim sensor cannot start"
	finish
endif

if !filereadable($HACKYSTAT_SENSORSHELL_HOME)
	echo "Can't read sensorshell jar at ".$HACKYSTAT_SENSORSHELL_HOME." Does this file exist? Vim sensor cannot start."
"	finish
endif

" These are the autocommands that repspond to VIM events that may change
" the current buffer being used. When the buffer changes, the location of 
" the swapfile might change and VIMHackystatSensor will need to know 
" where it is. The sensor reads the swapfile for the current buffer 
" being editing in the case that its a new and hasn't been saved and to
" access other misc. information. This may change in the future and the
" these autocommands will update the needed information directly to the
" sensor data file. Having this vim script update the needed data directly
" during the sample interval is inefficent or inreliable. In particular, 
" the autocommand CursorHold can call a function whenever the cursor
" does not move for a period of time, but not when it does move nor when
" Vim is in command mode.
"
" The sensor may be partially shut off (for privacy or non-relevant 
" editing work) by issuing :autocmd! HackystatSensor and re-enabled
" via "autocmd HackystatSensor
"
augroup HackystatSensor
	:autocmd VimEnter * call <SID>s:InitHSSensor()
	:autocmd VimLeave * call <SID>s:CloseHSData()
	:autocmd BufNewFile * call <SID>s:UpdateHSData()
	:autocmd BufReadPost * call <SID>s:UpdateHSData()
	:autocmd FileReadPost * call <SID>s:UpdateHSData()
	:autocmd BufWritePost * call <SID>s:UpdateHSData()
	:autocmd FileWritePost * call <SID>s:UpdateHSData()
	:autocmd BufEnter * call <SID>s:UpdateHSData()
	:autocmd BufLeave * call <SID>s:UpdateHSData()
	:autocmd BufCreate * call <SID>s:UpdateHSData()
	:autocmd BufDelete * call <SID>s:UpdateHSData()
	:autocmd CursorHold * call <SID>s:UpdateHSData()
:augroup END

" Map <CR> to UpdateHSData(). Between this and CursorHold the current buffer name and size data
" should generally be accurate. The only exception is when user leaves Vim in command mode
" or does not hit <CR> for a very long while when typing
let letter = "<CR>"
execute "inoremap <silent>" letter "<ESC>:call <SID>s:UpdateHSDataOnCR()<CR>" . letter
 
" This function is called when Vim first starts. It sets the time interval  
" the swapfile is updated and lets the user know the sensor
" is running. For fun, it
" also tells the swapfile to update whenever a given number of 
" characters are typed.
"
function <SID>s:InitHSSensor()
" VIM_SWAP_UPDATE_INTERVAL updatetime in miliseconds
if !exists("$VIM_SWAP_UPDATE_INTERVAL")
        echo "$VIM_SWAP_UPDATE_INTERVAL not defined - using default"
	let $VIM_SWAP_UPDATE_INTERVAL=30000
endif
	let &updatetime=$VIM_SWAP_UPDATE_INTERVAL

" tell vim to update the swap file whenever a given number of
" characters are edited
if !exists("$VIM_SWAP_CHARACTER_UPDATE_INTERVAL")
        echo "$VIM_SWAP_CHARACTER_UPDATE_INTERVAL not defined - using default"
        let $VIM_SWAP_CHARACTER_UPDATE_INTERVAL=400
endif
	let &updatecount=$VIM_SWAP_CHARACTER_UPDATE_INTERVAL
 
" start the VimHackystatSensor process
	let tmp = '(cd '.$HOME.'/.hackystat/vim; java -cp .:'.$HACKYSTAT_SENSORSHELL_HOME.' HSVimSensor -silent)'	
	let tmp = tmp.' >& /dev/null &'
	call system( tmp )
" make sure a vim data file exists before VimHackystatSensor starts <TBD>
	call <SID>s:UpdateHSData()
	echohl ErrorMsg
	echo "Hackystat Sensor Active"
	echohl None
endfunction


" Write the current buffer file location and size data to the Vim data path."  
" The process table will be checked each time UpdateHSData is called to
" see if VimHackystatSensor is running. If not, it will be re-started. 
" <TBD>
"
function <SID>s:UpdateHSData()
" Get the data about the active buffer 
	let s:currentBufData = SensorData()
	call system("echo ".s:currentBufData.$redirect_op.$HACKYSTAT_VIM_SENSOR_DATA_FILE)
"
" <TBD> restart VimHackystatSensor if needed
"
endfunction

function <SID>s:UpdateHSDataOnCR()

" First call regular UpdateHSData()
call  <SID>s:UpdateHSData()

" If update is done on keymap to <CR> then the mode must be reset
  " Save and reset the 'ignorecase' option.
  let save_ic = &ignorecase
  set noignorecase

  if strlen(getline(".")) > col(".")
    normal l
    startinsert
  else
    startinsert!
  endif

  " Restore the 'ignorecase' option.
  let &ignorecase = save_ic
endfunction

" Clean up by removing the Vim data file if possible. This lets 
" VimHackstatSensor know the editor has quit.
"
function <SID>s:CloseHSData()
	call system ("/bin/rm -f ".$HACKYSTAT_VIM_SENSOR_DATA_FILE)
endfunction

" Below are functions to get Hackystat data inside Vim in case we later
" find a way to write this data directly during the sample interval
" (maybe can communicate with SensorShell)
"
function CharCount()
	let lineNum = 1
	let size = 0
	while lineNum <= line("$")
		let lineNum = lineNum + 1
		let size = size + strlen(getline(lineNum))
	endwhile
	return size
endfunction

function ByteCount()
      let bufsize = line2byte(line("$") + 1) - 1
      " prevent negative numbers (non-existant buffers)
      if bufsize < 0
          let bufsize = 0
      endif
      " add commas
      let remain = bufsize
      let bufsize = ""
      while strlen(remain) > 3
          let bufsize = "," . strpart(remain, strlen(remain) - 3) . bufsize
          let remain = strpart(remain, 0, strlen(remain) - 3)
      endwhile
      let bufsize = remain . bufsize
      return bufsize
  endfunction
