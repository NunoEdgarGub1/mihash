function [resfn, dp] = demo_mutualinfo(ftype, dataset, nbits, varargin)
% PARAMS
%  ftype (string) from {'gist', 'cnn'}
%  dataset (string) from {'cifar', 'sun','nus'}
%  nbits (integer) is length of binary code
%  varargin: see get_opts.m for details

% get OSH-specific fields first
ip = inputParser;
ip.addParamValue('no_bins', 16, @isscalar);
ip.addParamValue('stepsize', 1, @isscalar);
ip.addParamValue('max_dif', 0, @isscalar); % regularizer parameter 
ip.addParamValue('decay', 0, @isscalar);
ip.addParamValue('sigmf_p', [1 0], @isnumeric);
ip.addParamValue('init_r_size', 500, @isscalar); % initial size of reservoir
ip.addParamValue('hloss', 0, @isscalar); % set 1 for nips 16 histogram loss
ip.addParamValue('epoch', 1, @isscalar);
ip.addParameter('methodID', 'mutual_info');
ip.KeepUnmatched = true;
ip.parse(varargin{:});
opts = ip.Results;
opts.identifier = sprintf('NoBins%d_StepSize%g_Decay%g_InitRSize%g_SGMFP%g-%g_MaxDif%g_Epoch%g_HLOSS%d', opts.no_bins, ...
        opts.stepsize, opts.decay, opts.init_r_size, opts.sigmf_p(1), opts.sigmf_p(2), opts.max_dif, opts.epoch, opts.hloss);
	
opts.batchSize  = 1;  % hard-coded

% get generic fields
opts = get_opts(opts, ftype, dataset, nbits, varargin{:});  % set parameters

% run demo
[resfn, dp] = demo(opts, @train_mutualinfo, @test_osh);
diary('off');
end
