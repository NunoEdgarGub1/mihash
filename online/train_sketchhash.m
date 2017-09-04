function [train_time, update_time, res_time, ht_updates, bits_computed_all] = ...
    train_sketch(Xtrain, Ytrain, thr_dist, prefix, test_iters, trialNo, opts)
% Copyright (c) 2017, Fatih Cakir, Kun He, Saral Adel Bargal, Stan Sclaroff 
% All rights reserved.
% 
% If used for please cite the below paper:
%
% "MIHash: Online Hashing with Mutual Information", 
% Fatih Cakir*, Kun He*, Sarah Adel Bargal, Stan Sclaroff
% (* equal contribution)
% International Conference on Computer Vision (ICCV) 2017
% 
% Usage of code from authors not listed above might be subject
% to different licensing. Please check with the corresponding authors for
% additional information.
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are met:
% 
% 1. Redistributions of source code must retain the above copyright notice, this
%    list of conditions and the following disclaimer.
% 2. Redistributions in binary form must reproduce the above copyright notice,
%    this list of conditions and the following disclaimer in the documentation
%    and/or other materials provided with the distribution.
% 
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
% ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
% WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
% DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
% ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
% (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
% ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
% (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
% SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
% 
% The views and conclusions contained in the software and documentation are those
% of the authors and should not be interpreted as representing official policies,
% either expressed or implied, of the FreeBSD Project.
%
%------------------------------------------------------------------------------
% Implementation of the SketchHash method as described in: 
%
% C. Leng, J. Wu, J. Cheng, X. Bai and H. Lu
% "Online Sketching Hashing"
% Computer Vision and Pattern Recognition (CVPR) 2015
%
% Training routine for SketchHash method.
%
% INPUTS
% 	Xtrain - (float) n x d matrix where n is number of points 
%       	         and d is the dimensionality 
%
% 	Ytrain - (int)   n x l matrix containing labels, for unsupervised datasets
% 			 might be empty, e.g., LabelMe.
%     thr_dist - (int)   For unlabelled datasets, corresponds to the distance 
%		         value to be used in determining whether two data instance
% 		         are neighbors. If their distance is smaller, then they are
% 		         considered neighbors.
%	       	         Given the standard setup, this threshold value
%		         is hard-wired to be compute from the 5th percentile 
% 		         distance value obtain through 2,000 training instance.
% 			 see load_gist.m . 
% 	prefix - (string) Prefix of the "checkpoint" files.
%   test_iters - (int)   A vector specifiying the checkpoints, see train.m .
%   trialNo    - (int)   Trial ID
%	opts   - (struct)Parameter structure.
%
% OUTPUTS
%  train_time  - (float) elapsed time in learning the hash mapping
%  update_time - (float) elapsed time in updating the hash table
%  res_time    - (float) elapsed time in maintaing the reservoir set
%  ht_updates  - (int)   total number of hash table updates performed
%  bit_computed_all - (int) total number of bit recomputations, see update_hash_table.m
 
% NOTES
% 	W is d x b where d is the dimensionality 
%            and b is the bit length / # hash functions
%

%%%%%%%%%%%%%%%%%%%%%%% GENERIC INIT %%%%%%%%%%%%%%%%%%%%%%%

% set up reservoir
reservoir = [];
reservoir_size = opts.reservoirSize;
if reservoir_size > 0
    reservoir.size = 0;
    reservoir.X    = [];
    if opts.unsupervised
	reservoir.Y = [];
    else
        reservoir.Y = zeros(0, size(Ytrain, 2));
    end
    reservoir.PQ   = [];
    reservoir.H    = [];  % mapped binary codes for the reservoir
end

% order training examples
train_ind = zeros(1, opts.epoch*opts.noTrainingPoints);
for e = 1:opts.epoch
    % randomly shuffle training points before taking first noTrainingPoints
    train_ind((e-1)*opts.noTrainingPoints+1:e*opts.noTrainingPoints) = ...
        randperm(size(Xtrain, 1), opts.noTrainingPoints);
end
opts.noTrainingPoints = opts.noTrainingPoints*opts.epoch;
%%%%%%%%%%%%%%%%%%%%%%% GENERIC INIT %%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%% SET UP SketchHash %%%%%%%%%%%%%%%%%%%%%%%
% convert parameters from opts to internal ones
% NOTE: W_lastupdate keeps track of the last W used to update the hash table
%       W_lastupdate is NOT the W from last iteration
W_lastupdate = W;
H = [];  % initial hash table

% for recording time
train_time  = 0;
update_time = 0;
res_time    = 0;

% bits computed
bits_computed_all = 0;

% HT updates
update_iters = [];

%%%%%%%%%%%%%%%%%%%%%%% SET UP SketchHash %%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%% STREAMING BEGINS! %%%%%%%%%%%%%%%%%%%%%%%
for batchInd = 1 : batchCnt



    % ---- reservoir update & compute new reservoir hash table ----
    t_ = tic;
    Hres_new = [];
    if reservoir_size > 0
        Xs = bsxfun(@minus, instFeatInBatch, instFeatAvePre);
	if ~isempty(Ytrain), Ys = Ytrain(ind, :); else, Ys = []; end;
        [reservoir, update_ind] = update_reservoir(reservoir, Xs, Ys, ...
            reservoir_size, W_lastupdate, opts.unsupervised);
        % compute new reservoir hash table (do not update yet)
        Hres_new = (W' * reservoir.X' > 0)';
    end


    % ---- determine whether to update or not ----
    if batchInd*opts.batchSize <= opts.sketchSize
        % special for SketchHash: fill sketch matrix first
        update_table = true;
        trigger_val  = 0;
    else
        [update_table, trigger_val] = trigger_update(batchInd, opts, ... 
            W_lastupdate, W, reservoir, Hres_new, opts.unsupervised, thr_dist);
    end
    res_time = res_time + toc(t_);


    % ---- hash table update, etc ----
    if update_table
        W_lastupdate = W;
        update_iters = [update_iters, batchInd];

        % update reservoir hash table
        if reservoir_size > 0
            reservoir.H = Hres_new;
        end

        % actual hash table update (record time)
        % TODO handle the mean subtraction in unified framework
        t_ = tic;
        X_cent = bsxfun(@minus, Xtrain, instFeatAvePre);  % centering
        [H, bits_computed] = update_hash_table(H, W_lastupdate, ...
            X_cent, Ytrain, update_iters, opts);
        bits_computed_all = bits_computed_all + bits_computed;
        update_time = update_time + toc(t_);
    end


    % ---- cache intermediate model to disk ----
    % CHECKPOINT
    if ismember(batchInd, test_iters)
        F = sprintf('%s_iter%d.mat', prefix, batchInd);
        save(F, 'W', 'W_lastupdate', 'H', 'bits_computed_all', ...
            'train_time', 'update_time', 'res_time', 'update_iters');

        logInfo(['*checkpoint*\n[T%02d] %s\n' ...
            '     (%d/%d) W %.2fs, HT %.2fs (%d updates), Res %.2fs\n' ...
            '     total BR = %g'], ...
            trialNo, opts.identifier, batchInd*opts.batchSize, opts.noTrainingPoints, ...
            train_time, update_time, numel(update_iters), res_time, ...
            bits_computed_all);
    end
end
%%%%%%%%%%%%%%%%%%%%%%% STREAMING ENDED! %%%%%%%%%%%%%%%%%%%%%%%

% save final model, etc
F = [prefix '.mat'];
save(F, 'instFeatAvePre', 'W', 'H', 'bits_computed_all', ...
    'train_time', 'update_time', 'res_time', 'test_iters', 'update_iters');

ht_updates = numel(update_iters);
logInfo('%d Hash Table updates, bits computed: %g', ht_updates, bits_computed_all);
logInfo('[T%02d] Saved: %s\n', trialNo, F);
end
