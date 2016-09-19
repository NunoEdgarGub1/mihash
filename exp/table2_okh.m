% for getting the final results in Table 2
%
demo_okh('cnn', 'places', 12, 'noTrainingPoints', 100e3, 'ntests', 2, ...
	'updateInterval', 100e3, 'labelspercls', 0, 'override', 0, ...
	'alpha', 0.1, 'c', 1, 'metric', 'prec_n3', 'ntrials', 3, 'showplots', 0)

demo_okh('cnn', 'places', 24, 'noTrainingPoints', 100e3, 'ntests', 2, ...
	'updateInterval', 100e3, 'labelspercls', 0, 'override', 0, ...
	'alpha', 0.1, 'c', 1, 'metric', 'prec_n3', 'ntrials', 3, 'showplots', 0)

demo_okh('cnn', 'places', 32, 'noTrainingPoints', 100e3, 'ntests', 2, ...
	'updateInterval', 100e3, 'labelspercls', 0, 'override', 0, ...
	'alpha', 0.1, 'c', 1, 'metric', 'prec_n3', 'ntrials', 3, 'showplots', 0)

demo_okh('cnn', 'places', 64, 'noTrainingPoints', 100e3, 'ntests', 2, ...
	'updateInterval', 100e3, 'labelspercls', 0, 'override', 0, ...
	'alpha', 0.1, 'c', 1, 'metric', 'prec_n3', 'ntrials', 3, 'showplots', 0)
