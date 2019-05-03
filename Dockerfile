FROM agguzman/terraform:0.11.7

RUN apt-get update && apt-get -y install \
  python \
  python-pip \
  awscli \
  curl \
  vim \
  openssh-client \
  git \
  jq

ENV AWS_ACCESS_KEY_ID=<access_key> \
   AWS_SECRET_ACCESS_KEY=<secret_key> \
   AWS_DEFAULT_REGION=<region>

ENV AWS_REGION $AWS_DEFAULT_REGION

VOLUME /infr /sshkeys /aws
