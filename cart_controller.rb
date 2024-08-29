module Marketplace
  # This class covers all the checkout and post-checkout functionality for "guest" checkout
  class CartController < Marketplace::BaseController

    # GET
    def after_payment_success
      ActiveRecord::Base.connected_to(role: :writing) do
        cart = Cart.find_by(id: params[:id])
        cart.paid!

        if current_user
          cart_manager = CartManager.new(session, current_user)
          Rails.cache.delete("#{cart.user_id}/carts")
          redirect_to marketplace_sale_success_path(cart_id: params[:id])
        else
          session[:cart_items] = []
          session[:processing_cart_id] = params[:id]
          session[:continue_as_guest] = nil
          redirect_to new_marketplace_user_session_path
        end
      end
    end

    # It's like the real checkout, but with no user logged in...
    # GET
    def checkout
      unless params[:seller_id].present?
        redirect_to show_marketplace_cart_index_path(current_market),
          error: I18n.t("controllers.carts.checkout.error") and return
      end

      if !user_signed_in? && session[:continue_as_guest].blank?
        session["previous_url"] = checkout_marketplace_cart_index_path(current_market)
        redirect_to new_marketplace_user_session_path(current_market, show_guest_login: true)
        return
      elsif session[:continue_as_guest].present?
        session["previous_url"] = for_sale_search_marketplace_collectibles_path(current_market)
      end

      data = params.permit(:seller_id, :shippingZone, :shippingState, :collectionInPerson, :selectedService).merge({
        market_id: current_market.id,
        user_address_id: params.dig(:address, :id)
      })

      ActiveRecord::Base.connected_to(role: :writing) do
        cart_manager = CartManager.new(session, current_user, current_market)
        @cart = CartService::Manager.new.checkout_cart(current_user, cart_manager.buyable_cart_items, OpenStruct.new(data))

        merchant_ids, errors = cart_manager.get_paypal_merchant_ids(params[:seller_id])
        @errors = errors if errors.present?
        @paypal_merchant_ids = merchant_ids if merchant_ids.present?
      end

      if session[:coupon_code].present? && session[:coupon_seller_id].present?
        @coupon_code = session[:coupon_code]
        @coupon_seller_id = session[:coupon_seller_id]
      end
      flash[:analytics] = AnalyticsEvents.get_event_for_market(
        :user_click_market_checkout, current_market.name
      )
    end

    # GET
    # TODO: refactor this full thing...
    def show
      cart_manager = CartManager.new(session, current_user, current_market)
      if params[:cancel_lock] && params.key?(:cart_id)
        ActiveRecord::Base.connected_to(role: :writing) do
          cart = Cart.find(params[:cart_id])
          cart.cancel_lock!
          flash.now[:notice] = "Your Checkout has timed-out. To reserve and purchase these items, please click the checkout button again. You will then have five minutes to complete your checkout." if params.key?(:flash)
        end
      end
      # If we have an ID, then we know it's a collectible and incoming from PPG / Widget
      # If we don't, then we should check the session store to see if we have
      # items, and if so, then create collectibles for all of them.
      # If we have a combination of catalog_item_ids + seller_id or
      # original_site_ids + seller_id + market_id then add the first collectible for that
      if params[:id].present?
        cart_manager.add_or_remove_cart_item(params[:id])
      end
      @zone = params[:zone] || session[:cart_zone] || "Lower 48 States"

      # If we have a logged in user, collectible_in_cart is the source of truth.
      if current_user.present?
        @default_address = UserAddressSerializer.new(current_user.default_address).serialized_json
      end

      flash[:analytics] = AnalyticsEvents.get_event_for_market(
        :user_click_market_cart, current_market.name
      )
    end
  end
end
