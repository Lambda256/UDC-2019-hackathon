# NOTE:
# This order book has some unrealistic limitations to be simplified (for hackathon):
# 1. Taker can only take the full amount (no partial fill)
# 2. Orders with the same price won't be groupped on the list
# 3. Taker can only take the lowest & oldest (if the price is the same) order

class Order < ApplicationRecord
  belongs_to :private_token
  belongs_to :maker, class_name: :User
  belongs_to :taker, class_name: :User, optional: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :price, presence: true, numericality: { greater_than: 0 }
  validate :price_should_greater_than_sale_price

  after_create :set_balance_pending!

  scope :opened, -> { where(taker_id: nil) }

  def price_should_greater_than_sale_price
    if self.private_token.nil?
      errors.add(:private_token, "is invalid")
      throw :abort
    end
    if self.price >= self.private_token.current_price
      errors.add(:price, "must be smaller than sale price")
      throw :abort
    end
  end

  def set_balance_pending!
    user_token = UserPrivateToken.find_by(private_token: self.private_token_id, user_id: self.maker_id)
    if user_token.nil? || user_token.balance < amount
      errors.add(:amount, 'cannot be bigger than your balance')
      throw :abort
    end

    # Inside the Order.create transaction
    user_token.lock!
    user_token.balance -= amount
    user_token.pending_balance += amount
    user_token.save!
  end

  def self.best_bids(private_token_id, limit = 10)
    where(private_token: private_token_id, taker_id: nil).order(price: :asc, created_at: :asc).limit(limit)
  end

  def takeable?
    best_bid = self.class.best_bids(self.private_token_id, 1).first
    best_bid == self
  end

  def take!(taker_id)
    # NOTE: Should be commented out when production
    # raise 'You cannot take your own order' if taker_id == self.maker_id

    self.taker_id = taker_id
    ActiveRecord::Base.transaction do
      Transaction.sell!(self.private_token_id, self.maker_id, self.taker_id, self.price, self.amount)

      self.taker_id = taker_id
      self.save!
    end

    # puts "User #{self.taker.name} purchased User #{self.maker.name}'s #{self.amount} #{self.private_token.symbol} at #{self.price}"
  end
end
