{
  #-----------------------------------------------
  # main function -- BMAR
  #-----------------------------------------------
  # input:
  # Data -- time-series Data
  # Order -- order of ar process;
  #             intercept term will be included
  #             eg: order 1 is
  #               y_t = b1 + b2*y_{t-1}  
  
  # output:
  # list:
  # [[1]] beta
  # [[2]] accept rate
  # [[3]] burnin chain
  # [[4]] chain
  
  
  # init_f = 0
  # init_beta = runif(0,1)
  # iterations = 40,000 with 25,000 burnin
  # a = binar search, around 35%
  # df = 5
  BMAR <- function( Data, order = 1){ 
    
    #-----------------------------------------------
    # check the input
    #-----------------------------------------------
    # Data
    SampleSize = length(Data)
    y = matrix(Data, SampleSize, 1)
    # order
    order = matrix( (order+1) , 1, 1)      
    
    #-----------------------------------------------
    # Burnin MCMC
    #-----------------------------------------------
    
    # init_beta 
    init_beta = runif(order,0,1)
    
    # find optim a
    a = 1
    r.b_a = 1
    l.b_a = 0
    
    tem_target = quick_accept_rate(y, order, a, 1000, init_beta)
    
    # ensure right bound of a is large enough
    while(tem_target > 0.5){
      r.b_a = r.b_a + 1
      a = r.b_a
      tem_target = quick_accept_rate(y, order, a, 1000, init_beta)
    }
    
    # find optim a by binary search
    while( abs(tem_target - 0.35) > 0.05 ){
      if( tem_target > 0.4 ){
        l.b_a = a
        a = (a + r.b_a)
        tem_target = quick_accept_rate(y, order, a, 1000, init_beta)
      }else{
        r.b_a = a
        a = (a + l.b_a)/2
        tem_target = quick_accept_rate(y, order, a, 1000, init_beta)
      }
    }
    
    # MCMC
    Burnin_chain <- MCMC(y, order, a, 25000, init_beta)
    
    #-----------------------------------------------
    # RW-MCMC
    #-----------------------------------------------
    
    # set the initial
    RW_initial <- Burnin_chain[25000,]
    
    # find optim a
    a = 1
    r.b_a = 1
    l.b_a = 0
    
    tem_target = quick_accept_rate(y, order, a, 1000, RW_initial)
    
    # ensure right bound of a is large enough
    while(tem_target > 0.5){
      r.b_a = r.b_a + 1
      a = r.b_a
      tem_target = quick_accept_rate(y, order, a, 1000, RW_initial)
    }
    
    # find optim a by binary search
    while( abs(tem_target - 0.3) > 0.05 ){
      if( tem_target > 0.35 ){
        l.b_a = a
        a = (a + r.b_a)
        tem_target = quick_accept_rate(y, order, a, 1000, RW_initial)
      }else{
        r.b_a = a
        a = (a + l.b_a)/2
        tem_target = quick_accept_rate(y, order, a, 1000, RW_initial)
      }
    }
    
    # MCMC
    RW_chain <- MCMC(y, order, a, 15000, RW_initial)
    
    #-----------------------------------------------
    # report results
    #-----------------------------------------------
    
    Accept = matrix(0, 1, 2)
    Accept[1] = 1 - mean( duplicated(Burnin_chain[,1]))
    Accept[2] = 1 - mean( duplicated(RW_chain[,1]))
    
    colnames(Accept) <- c('burn_in','random_walk')
    
    # report beta and variance
    mean_BI = apply( Burnin_chain, 2, mean)
    sd_BI = apply( Burnin_chain, 2, sd)
    mean_RW = apply( RW_chain, 2, mean)
    sd_RW = apply( RW_chain, 2, sd)
    beta <- matrix(c( mean_BI, sd_BI, mean_RW, sd_RW), 4, order, byrow = T)
    rownames(beta) <- c('BI_Coeff.','BI_S.E','RW_Coeff.','RW_S.E')
    
    output <- list(beta,Accept,Burnin_chain,RW_chain)
    
    return(output)
  }
  
  #-----------------------------------------------
  #       proposal
  #-----------------------------------------------
  #   using t-proposal
  #   beta_{proposal} = beta_{last period} + t
  #   where t ~ t(5)
  #  
  #   input row vector \beta
  #   parameter a
  #   return row vector \beta
  proposal_beta <- function(param, a){
    
    # check input
    order = length(param)
    param <- matrix(param, 1, order)
    
    # update proposal
    param = param + t(diag(a,order)%*%rt(order,5))
    
    return(param)
  }
  
  #-----------------------------------------------
  #       MCMC Sampler
  #-----------------------------------------------
  MCMC <- function( y, order, a, Iterations, init_beta){
    #-----------------------------------------------
    # conclude infromations needs
    #-----------------------------------------------  
    
    # creat the matrix to store chain
    chain <- array( dim = c(Iterations, order))
    # input initial value of the chain
    chain[1,] <- matrix(init_beta , 1, order)
    
    #-----------------------------------------------
    # MCMC process
    #-----------------------------------------------
    for ( i in 2:Iterations){
      # propose
      proposal = proposal_beta( chain[i-1,], a)
      
      # accept/reject
      prob = exp( posterior(proposal, y) - posterior( chain[i-1,], y))
      
      if ( runif(1) < prob ){
        chain[i,] <- proposal
      }else{
        chain[i,] <- chain[i-1,]
      }
      
    }
    return(chain)
  } 
  
  #-----------------------------------------------
  #       quick-accept-rate
  #-----------------------------------------------
  
  quick_accept_rate = function( y, order, a, Iterations, init_beta){
    tem_chain = MCMC(y, order, a, Iterations, init_beta)
    tem_accept = 1 - mean(duplicated(tem_chain[,1]))
    return(tem_accept)
  }
  
  #-----------------------------------------------
  #       posterior function
  #-----------------------------------------------
  #    priors of beta_i : \propto 1
  #    Likelihood : Skewed-Laplace distribution ~ SL(0,\tau,\alpha)
  #    posterior is [\sum^{n}_{t=2} \frac{1}{2} \abs{ y_t - f_{t}(\beta) }]^{-n}
  posterior <- function(param, y){
    #-----------------------------------------------
    # check input
    #-----------------------------------------------
    order = length(param)
    beta = matrix(param, order, 1)
    SampleSize = length(y)
    y <- matrix(y, SampleSize, 1)
    f <- matrix(0,SampleSize,1)
    
    # set scalar to store sum
    t <- 0 
    
    #-----------------------------------------------
    # calculate posterior for given Data
    #-----------------------------------------------
    Y = matrix(1, order, SampleSize-order+1)
    for(i in 2:order){
      Y[i,] = y[(SampleSize-i+1):(order-i+1)]
    }
    
    f[SampleSize:order] = t(beta) %*% Y 
    f[SampleSize:order] = (abs(y[SampleSize:order] - f[SampleSize:order]))/2
    
    t <- (-(SampleSize-order+1))*log(sum(f[SampleSize:order]))
    
    return(t)
  }
  

  #-----------------------------------------------
  #       BIC_BMAR
  #-----------------------------------------------

  # input Data, max order
  # using BIC select order automatically, by grid search

  BIC_BMAR = function( Data, max_order = 10){

    tem_beta = list()
    tem_ar = list()
    BIC = matrix(0,1,max_order)

    for(j in 1:max_order){
      
      # estimate Data with order j
      results = BMAR(Data, j)
      # record results
      tem_beta = c(tem_beta, list(results[[1]][3,]))
      tem_ar = c(tem_ar, list(results[[2]]))

      # calculate BIC
      # BIC = n*log(sigma) - p/2*log(n)
      # where sigma = n^{-1} |sum[y_t] - x\theta]|
      p = (j+1)
      n = length(Data)
      Y= matrix(1, p, n-p+1)
      for( i_row in 2:p){
        Y[i_row,] = Data[(n-i_row+1):(p-i_row+1)]
      }
      sigma = sum( abs( Data[n:p] - tem_beta[[j]] %*% Y ) )/(n-p+1)
      BIC[1,max_order] = (n-p+1)*log(sigma) - (p)/2*log((n-p+1)) 
    }
    order = which.min(BIC)

    res = list(order, tem_beta[[order]], tem_ar[[order]])
    return(res)
  }
  
}
