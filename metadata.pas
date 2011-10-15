{*
 *  hz - AAC, AACplus, AACplusV2 Icecast source client
 *  Copyright (C) 2006 Roman Butusov <reaxis at mail dot ru>
 *
 *  This program is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Library General Public
 *  License as published by the Free Software Foundation; either
 *  version 2 of the License, or (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Library General Public License for more details.
 *
 *  You should have received a copy of the GNU Library General Public
 *  License along with this library; if not, write to the Free
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *}

unit metadata;
{$MODE DELPHI}
{$H+}

interface

uses SysUtils, Classes, net,
     tags, cuesheet, timing, config, b64, script, log;


type
  TUpdateThread = class(TThread)
  private
    fname: string;
  protected
    procedure Execute; override;
  public
    constructor Create(filename: string); overload;
    constructor Create; overload;
  end;

procedure metadata_update(filename: string); overload;
procedure metadata_update(time: dword); overload;
function metadata_cueload(cuename: string): boolean;

implementation

function URLEncode(const S: string): string;
var
  Idx: Integer; // loops thru characters in string
begin
  Result := '';
  for Idx := 1 to Length(S) do
  begin
    if S[Idx] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '.'] then
        Result := Result + S[Idx]
    else
      Result := Result + '%' + IntToHex(Ord(S[Idx]), 2);
  end;
end;

procedure log_metadata_update(Artist, Title: string);
begin
  hz_logln_term(#13'Getting tags...                                          ', LOG_DEBUG);
  hz_log('Getting tags...', LOG_DEBUG);
  if Artist = '' then Artist := 'N/A';
  if Title  = '' then Title  := 'N/A';
  //
  hz_log_term(#13'                                                           '#13, LOG_INFO);
  hz_log_both('Artist : ' + Artist, LOG_INFO);
  hz_log_both('Title  : ' + Title, LOG_INFO);
end;

function format_metadata(Artist, Title: string): string;
begin
  Result := script_formatmetadata(Artist, Title);
  if Result <> '' then exit;
  if Artist <> '' then
    Result := Artist + ' - ' + Title
  else
    Result := Title;
  if Result = '' then
    Result := Opts.name;
end;


function get_tags(filename: string): string;
var
  Artist, Title: string;
begin
  tag_get_id3v1(filename, Artist, Title);
  if (Artist <> '') or (Title <> '') then
  begin
     log_metadata_update(Artist, Title);
     Result := format_metadata(Artist, Title);
     exit;
  end;
  tag_get_id3v2(filename, Artist, Title);
  if (Artist <> '') or (Title <> '') then
  begin
     log_metadata_update(Artist, Title);
     Result := format_metadata(Artist, Title);
     exit;
  end;

  log_metadata_update(Artist, Title);
  // if there are no tags, then use the station name as a tag
  Result := format_metadata(Artist, Title);
end;

function get_tags_cue: string;
var
  Artist, Title: string;
begin
  cue_get_tags(Artist, Title);
  if (Artist <> '') or (Title <> '') then
  begin
     log_metadata_update(Artist, Title);
     Result := format_metadata(Artist, Title);
     exit;
  end;

  log_metadata_update(Artist, Title);
  // if there are no tags, then use the station name as a tag
  Result := format_metadata(Artist, Title);
end;


procedure TUpdateThread.Execute;
var
  Sock: integer;
  headers: string;
  metadata: string;
begin
  // get metadata from id3v1 or id3v2 tags
  if fname <> '' then
    metadata := get_tags(fname)
  // or from cuesheet
  else
    metadata := get_tags_cue;
  //writeln('metadata = ', metadata);
  metadata := script_onmetadata(metadata);
  hz_log_term(#13'                                                   '#13, LOG_INFO);
  hz_log_both('Metadata set to: ' + metadata, LOG_INFO);
  metadata := URLEncode(metadata);

  // connect to server and send the metadata
  if not net_connect(Opts.host, Opts.port, sock) then exit;
  if Opts.Server = 'shoutcast' then
    headers := 'GET /admin.cgi?pass=' + UrlEncode(Opts.password) +
      '&mode=updinfo&song=' + metadata + ' HTTP/1.0' + crlf +
      'User-Agent: (Mozilla Compatible)' +
      crlf + crlf
  else
    headers := 'GET /admin/metadata?mode=updinfo&mount=/' + Opts.mount +
      '&song=' + metadata + ' HTTP/1.0' + crlf +
      'User-Agent: hz/' + version + crlf +
      'Authorization: Basic ' + EncodeBase64('source:' + Opts.password) +
      crlf + crlf;
  net_send(Sock, headers[1], length(headers));
  pause(100);
  net_close(Sock);
end;

constructor TUpdateThread.Create(filename: string); overload;
begin
  fname := filename;
  inherited Create(true);
  FreeOnTerminate := True;
  Resume;
end;

constructor TUpdateThread.Create; overload;
begin
  fname := '';
  inherited Create(true);
  FreeOnTerminate := True;
  Resume;
end;

procedure metadata_update(filename: string); overload;
var
  thr: TUpdateThread;
begin
  thr := TUpdateThread.Create(filename);
end;

procedure metadata_update(time: dword); overload;
var
  thr: TUpdateThread;
begin
  if cue_isupdate(time) then
    thr := TUpdateThread.Create;
end;

function metadata_cueload(cuename: string): boolean;
begin
  Result := cue_load(cuename);
end;

end.
