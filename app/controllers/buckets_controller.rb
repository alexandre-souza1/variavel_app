class BucketsController < ApplicationController
  def create
    @action_plan = ActionPlan.find(params[:action_plan_id])

    @bucket = @action_plan.buckets.build(bucket_params)
    @bucket.position = @action_plan.buckets.count

    if @bucket.save
      redirect_to action_plan_path(@action_plan)
    else
      redirect_to action_plan_path(@action_plan), alert: "Erro ao criar bucket"
    end
  end

  def update
    @bucket = Bucket.find(params[:id])

    if @bucket.update(bucket_params)
      head :ok
    else
      head :unprocessable_entity
    end
  end

  def destroy
    @bucket = Bucket.find(params[:id])
    action_plan = @bucket.action_plan

    @bucket.destroy

    redirect_to action_plan_path(action_plan)
  end

private

  def bucket_params
    params.require(:bucket).permit(:name)
  end
end
