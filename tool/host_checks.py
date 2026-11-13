"""Exercise the real JSONL host in memory only. Never omit --demo."""
import argparse, json, subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--dotnet', default=str(root.parent / '.dotnet9sdk/dotnet.exe'))
dotnet = parser.parse_args().dotnet
host = root / 'native/ControlHost/bin/Release/net9.0-windows/GO27Q32.ControlHost.dll'
proc = subprocess.Popen([str(dotnet), str(host), '--demo'], stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8')
sequence = 0
checks = 0
def call(method, args=None, valid=True):
    global sequence
    sequence += 1
    proc.stdin.write(json.dumps({'id': sequence, 'method': method, 'args': args or {}}) + '\n')
    proc.stdin.flush()
    result = json.loads(proc.stdout.readline())
    assert result['id'] == sequence and result['ok'] == valid, result
    return result.get('result')
def check(condition, name):
    global checks
    assert condition, name
    checks += 1
    print('PASS: ' + name)
try:
    init = call('init'); settings = init['settings']
    device = [f for f in init['features'] if f['DeviceSetting']]
    check(init['demo'] and len(init['features']) == 27 and len(device) == 11, '16 picture controls and 11 manual device controls / explicit demo')
    call('captureHdrPreset', {'preset': 'HDR显示'}, valid=False)
    call('hdrProbeInfo', valid=False)
    check('hdrProbe' not in init['state'], 'HDR preset sampling endpoints and state removed')
    check([p['Value'] for p in init['hdrPresets']] == list(range(5)), 'HDR command choices separated from readable SDR features')
    call('hdrPreset', {'value': 0}, valid=False)
    check(call('state').get('hdrPresetRequest') is None, 'HDR command rejected in SDR without a request record')
    state = call('set', {'feature': 'joystickUp', 'value': 13})
    check(state['values']['joystickUp']['Value'] == 13 and not state['canUndo'] and not state['dirty'], 'joystick command value does not create picture undo or dirty state')
    call('set', {'feature': 'joystickUp', 'value': 2}, valid=False)
    call('set', {'feature': 'osdTimeout', 'value': 6}, valid=False)
    check(call('state')['values']['joystickUp']['Value'] == 13, 'sparse joystick commands reject dropdown indices and out of range OSD values')
    state = call('set', {'feature': 'brightness', 'value': 72})
    check(state['values']['brightness']['Value'] == 72 and state['canUndo'], 'write readback / undo snapshot')
    call('set', {'feature': 'osdTimeout', 'value': 4})
    check(call('undo')['values']['brightness']['Value'] == 50, 'undo restores confirmed brightness')
    check(call('state')['values']['osdTimeout']['Value'] == 4, 'picture undo preserves independent device preferences')
    call('set', {'feature': 'crosshair', 'value': 5}, valid=False)
    check(call('set', {'feature': 'crosshair', 'value': 4})['values']['crosshair']['Value'] == 4, 'only five confirmed crosshair choices')
    call('hdr', {'enabled': True})
    call('set', {'feature': 'pictureMode', 'value': 1}, valid=False)
    check(call('state')['hdr']['ActiveHdr'], 'HDR forbids SDR picture-mode writes')
    sdr_only = ['brightness','contrast','pictureMode','sharpness','blackEqualizer','colorVibrance','gamma','colorTemperature','lowBlueLight','superResolution','overdrive']
    for feature in sdr_only:
        call('set', {'feature': feature, 'value': 0}, valid=False)
    check(not set(sdr_only).intersection(call('state')['values']), 'HDR blocks regular picture writes and does not expose SDR shadow readings')
    before_preset = call('state')
    for value in (0, 0, 1, 2, 3, 4):
        state = call('hdrPreset', {'value': value})
        check(state['hdrPresetRequest']['Value'] == value and 'pictureMode' not in state['values'] and not state['canUndo'], f'HDR preset {value} is a request, not a confirmed E7 reading or undoable state')
    check(state['values'] == before_preset['values'], 'HDR preset command does not modify any other picture setting')
    call('hdrPreset', {'value': 5}, valid=False)
    call('hdrPreset', {'value': -1}, valid=False)
    check(call('state')['hdrPresetRequest']['Value'] == 4, 'invalid HDR values preserve the last successful request')
    call('apply', {'id': 'daily'})
    state = call('state'); check(not state['hdr']['ActiveHdr'] and state['values']['brightness']['Value'] == 50, 'profile HDR policy and correct SDR bank')
    check(state['hdrPresetRequest'] is None, 'leaving HDR clears the session request label')
    old = json.loads(json.dumps(settings)); old['Profiles'][1]['HdrValues'] = {'brightness':80, 'contrast':50, 'pictureMode':9,'crosshair':3,'refreshOverlay':1,'freeSync':1,'volume':42}
    old['Profiles'][1]['HdrPreset'] = 2
    check(call('settings', old)['Profiles'][1]['HdrValues']['brightness'] == 80, 'legacy data preserved when loading settings')
    state = call('apply', {'id':'game'})
    check(state['hdrPresetRequest']['Value'] == 2 and not set(sdr_only).intersection(state['values']), 'HDR profile applies preset without legacy E7 or brightness')
    check(all(state['values'][k]['Value']==v for k,v in {'crosshair':3,'refreshOverlay':1,'freeSync':1,'volume':42}.items()), 'HDR preset and independent profile controls both apply')
    old['Profiles'][1]['HdrPreset'] = None
    old['Profiles'][1]['HdrValues']['crosshair'] = 4
    call('settings', old)
    state = call('apply', {'id':'game'})
    check(state['values']['crosshair']['Value']==4, 'HDR profile applies crosshair with Keep Current Preset')
    call('apply', {'id':'daily'})
    call('settings', settings)
    invalid = json.loads(json.dumps(settings)); invalid['Profiles'][0]['HdrPreset'] = 5
    call('settings', invalid, valid=False)
    invalid = json.loads(json.dumps(settings)); invalid['Profiles'][0]['Values']['input'] = 0
    call('settings', invalid, valid=False)
    for f in device:
        for bank in ('Values', 'HdrValues'):
            invalid = json.loads(json.dumps(settings))
            invalid['Profiles'][0][bank][f['Id']] = f['Choices'][0]['Value'] if f['Choices'] else 0
            call('settings', invalid, valid=False)
    check(True, 'all manual device controls rejected in both profile banks')
    check(call('init')['settings']['Profiles'][0]['Id'] == 'daily', 'invalid imports rejected before replacing settings')
    edited = json.loads(json.dumps(settings)); edited['StartMinimized'] = True
    check(call('settings', edited)['StartMinimized'], 'desktop preference round trip')
    edited['Language'] = 'en'
    check(call('settings', edited)['Language'] == 'en', 'explicit app language preference round trip')
    invalid = json.loads(json.dumps(edited)); invalid['Language'] = 'fr'
    call('settings', invalid, valid=False)
    check(call('settings', edited)['Language'] == 'en', 'unsupported language rejected without losing stored preference')
    call('automatic', {'enabled': True}); call('set', {'feature': 'brightness', 'value': 20}, valid=False)
    check(call('state')['automatic'], 'automation owns hardware while active')
    call('hdrPreset', {'value': 1}, valid=False)
    check(call('state')['automatic'], 'invalid SDR preset request does not pause active rules')
    state = call('hdr', {'enabled': True})
    check(state['hdr']['ActiveHdr'] and not state['automatic'], 'manual HDR enable pauses automation before the change')
    call('automatic', {'enabled': True})
    state = call('hdr', {'enabled': False})
    check(not state['hdr']['ActiveHdr'] and not state['automatic'], 'manual HDR disable remains usable while rules are active')
    call('hdr', {'enabled': True})
    call('automatic', {'enabled': True})
    state = call('hdrPreset', {'value': 2})
    check(state['hdrPresetRequest']['Value'] == 2 and not state['automatic'], 'manual HDR preset pauses rules without changing other controls')
    check(call('settings', edited)['Profiles'] == edited['Profiles'], 'manual HDR takeover preserves saved profiles')
    call('automatic', {'enabled': True})
    call('captureHdrPreset', {'preset': 'HDR娓告垙'}, valid=False)
    state = call('set', {'feature': 'ledIndicator', 'value': 2})
    check(state['automatic'] and state['values']['ledIndicator']['Value'] == 2, 'device preferences remain editable during application automation')
    call('automatic', {'enabled': False})
    call('hdr', {'enabled': False})
    check(call('set', {'feature': 'brightness', 'value': 20})['values']['brightness']['Value'] == 20, 'pause restores manual control')
    before = call('state')
    call('timer', {'mode': 2, 'minutes': 0, 'seconds': 60}, valid=False)
    call('timer', {'mode': 3, 'minutes': 0, 'seconds': 0}, valid=False)
    call('set', {'feature': 'timerDuration', 'value': 100}, valid=False)
    check(call('state')['values'] == before['values'], 'invalid timer inputs and raw writes rejected before mutation')
    state = call('timer', {'mode': 2, 'minutes': 0, 'seconds': 0})
    check(state['values']['timerDuration']['Value'] == 1280 and state['values']['timerRunning']['Value'] == 1, 'zero countdown defaults to five minutes with packed encoding')
    check(state['canUndo'] == before['canUndo'] and state['dirty'] == before['dirty'], 'timer operations preserve picture undo and dirty state')
    check(call('timerPause', {'paused': True})['values']['timerRunning']['Value'] == 0, 'timer pause readback')
    check(call('timerPause', {'paused': False})['values']['timerRunning']['Value'] == 1, 'timer continue readback')
    check(call('timer', {'mode': 1, 'minutes': 99, 'seconds': 59})['values']['timerDuration']['Value'] == 0, 'count up resets to zero')
    check(call('timer', {'mode': 2, 'minutes': 99, 'seconds': 59})['values']['timerDuration']['Value'] == 25403, '99:59 uses packed bytes rather than reported max 9960')
    call('timer', {'mode': 0, 'minutes': 0, 'seconds': 0})
    call('timerPause', {'paused': False}, valid=False)
    check(call('set', {'feature': 'assistPosition', 'value': 258})['values']['assistPosition']['Value'] == 258, 'bottom right position keeps sparse raw value')
    call('set', {'feature': 'assistPosition', 'value': 3}, valid=False)
    call('shutdown'); proc.wait(timeout=10)
    check(proc.returncode == 0, 'graceful host shutdown')
    print(f'{checks} host checks passed; no hardware accessed.')
finally:
    if proc.poll() is None: proc.kill()
