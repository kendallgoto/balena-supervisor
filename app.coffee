fs = require('fs')
express = require('express')
async = require('async')
bootstrap = require('./bootstrap')
state = require('./state')
settings = require('./settings')
request = require('request')
Application = require('./application')

console.log('Supervisor started..')

hakiApp = null

tasks = [
	(callback) ->
		if state.get('virgin')
			console.log('Device is virgin. Bootstrapping')
			handler = (error) ->
				if error
					console.log('Bootstrapping failed with error', error)
					console.log('Trying again in 10s')
					setTimeout((-> bootstrap(handler)), 10000)
				else
					console.log('Bootstrapping successful')
					state.set('virgin', false)
					callback()
			bootstrap(handler)
		else
			console.log("Device isn't a virgin")
			callback()
	(callback) ->
		fs.writeFile('/sys/class/leds/led0/trigger', 'none', callback)
	(callback) ->
		hakiApp = new Application(state.get('gitUrl'), '/home/haki/hakiapp', 'haki')

		hakiApp.on 'pre-init', ->
			request(
				uri: "#{settings.API_ENDPOINT}/ewa/device?$filter=uuid eq '#{state.get('uuid')}'"
				method: 'PATCH'
				json:
					status: 'Initialising'
			)

		hakiApp.on 'post-init', ->
			request(
				uri: "#{settings.API_ENDPOINT}/ewa/device?$filter=uuid eq '#{state.get('uuid')}'"
				method: 'PATCH'
				json:
					status: 'Idle'
			)

		hakiApp.on 'pre-update', ->
			request(
				uri: "#{settings.API_ENDPOINT}/ewa/device?$filter=uuid eq '#{state.get('uuid')}'"
				method: 'PATCH'
				json:
					status: 'Updating'
			)

		hakiApp.on 'post-update', (hash) ->
			request(
				uri: "#{settings.API_ENDPOINT}/ewa/device?$filter=uuid eq '#{state.get('uuid')}'"
				method: 'PATCH'
				json:
					status: 'Idle'
					commit: state.get('gitHash')
			)

		hakiApp.on 'start', ->
			request(
				uri: "#{settings.API_ENDPOINT}/ewa/device?$filter=uuid eq '#{state.get('uuid')}'"
				method: 'PATCH'
				json:
					status: 'Running'
			)

		hakiApp.on 'stop', ->
			request(
				uri: "#{settings.API_ENDPOINT}/ewa/device?$filter=uuid eq '#{state.get('uuid')}'"
				method: 'PATCH'
				json:
					status: 'Idle'
			)

		if not state.get('appInitialised')
			console.log('Initialising app..')
			hakiApp.init((error) ->
				if error then return callback(error)
				state.set('appInitialised', true)
				callback()
			)
		else
			console.log('App already initialised')
			callback()
	(callback) ->
		console.log('Fetching new code..')
		hakiApp.update(callback)
	(callback) ->
		console.log('Starting the app..')
		hakiApp.start(callback)
]

async.series(tasks, (error) ->
	if error
		console.error(error)
	else
		console.log('Everything is fine :)')
)

app = express()

app.post('/blink', (req, res) ->
	state = 0
	toggleLed = ->
		state = (state + 1) % 2
		fs.writeFileSync(settings.LED_FILE, state)

	interval = setInterval(toggleLed, settings.BLINK_STEP)
	setTimeout(->
		clearInterval(interval)
		fs.writeFileSync(settings.LED_FILE, 0)
		res.send(200)
	, 5000)
)

app.post('/update', (req, res) ->
	hakiApp.update((error) ->
		if error
			res.send(500)
		else
			res.send(204)
	)
)

app.listen(80)
