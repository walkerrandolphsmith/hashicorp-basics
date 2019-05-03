
export AWS_ACCESS_KEY_ID=XXXX
export AWS_SECRET_ACCESS_KEY=XXXX
export AWS_DEFAULT_REGION=us-east-1

function packer() {
  # not implemented
  docker run \
    -it hashicorp/packer:full \
    -v $PWD/packer:/ \
    build vault.config
}

function tf() {
  echo $PWD

  specified_user=$1;
  config=$2;

  user="1000:1000"
  [ "$specified_user" == "root" ] && user="0:0"
  docker image build -f ./Dockerfile -t terra $PWD && \
  docker container run \
      -it \
      --rm \
      -v $PWD/terraform/$config:/config \
      -u ${user} \
      -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
      -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
      -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} \
      terra
}


command=$1
shift;
rest=$@

case $command in
    tf)
        tf $rest
        ;;
    packer)
        packer $rest
        ;;
    *)
        echo "Option not recognized."
        exit 1
esac