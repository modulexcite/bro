#include "CounterVector.h"

#include <limits>
#include "BitVector.h"
#include "Serializer.h"

using namespace probabilistic;

CounterVector::CounterVector(size_t width, size_t cells)
  : bits_(new BitVector(width * cells)),
    width_(width)
  {
  }

CounterVector::CounterVector(const CounterVector& other)
	: bits_(new BitVector(*other.bits_)),
	  width_(other.width_)
  {
  }

CounterVector::~CounterVector()
  {
  delete bits_;
  }

bool CounterVector::Increment(size_type cell, count_type value)
  {
  assert(cell < Size());
  assert(value != 0);
  size_t lsb = cell * width_;
  bool carry = false;
  for ( size_t i = 0; i < width_; ++i )
    {
    bool b1 = (*bits_)[lsb + i];
    bool b2 = value & (1 << i);
    (*bits_)[lsb + i] = b1 ^ b2 ^ carry;
    carry = ( b1 && b2 ) || ( carry && ( b1 != b2 ) );
    }
  if ( carry )
    for ( size_t i = 0; i < width_; ++i )
      bits_->Set(lsb + i);
  return ! carry;
  }

bool CounterVector::Decrement(size_type cell, count_type value)
  {
  assert(cell < Size());
  assert(value != 0);
  value = ~value + 1; // A - B := A + ~B + 1
  bool carry = false;
  size_t lsb = cell * width_;
  for ( size_t i = 0; i < width_; ++i )
    {
    bool b1 = (*bits_)[lsb + i];
    bool b2 = value & (1 << i);
    (*bits_)[lsb + i] = b1 ^ b2 ^ carry;
    carry = ( b1 && b2 ) || ( carry && ( b1 != b2 ) );
    }
  return carry;
  }

CounterVector::count_type CounterVector::Count(size_type cell) const
  {
  assert(cell < Size());
  size_t cnt = 0, order = 1;
  size_t lsb = cell * width_;
  for (size_t i = lsb; i < lsb + width_; ++i, order <<= 1)
    if ((*bits_)[i])
      cnt |= order;
  return cnt;
  }

CounterVector::size_type CounterVector::Size() const
  {
  return bits_->Size() / width_;
  }

size_t CounterVector::Width() const
  {
  return width_;
  }

size_t CounterVector::Max() const
  {
  return std::numeric_limits<size_t>::max()
    >> (std::numeric_limits<size_t>::digits - width_);
  }

CounterVector& CounterVector::Merge(const CounterVector& other)
  {
  assert(Size() == other.Size());
  assert(Width() == other.Width());
  for ( size_t cell = 0; cell < Size(); ++cell )
    {
    size_t lsb = cell * width_;
    bool carry = false;
    for ( size_t i = 0; i < width_; ++i )
      {
      bool b1 = (*bits_)[lsb + i];
      bool b2 = (*other.bits_)[lsb + i];
      (*bits_)[lsb + i] = b1 ^ b2 ^ carry;
      carry = ( b1 && b2 ) || ( carry && ( b1 != b2 ) );
      }
    if ( carry )
      for ( size_t i = 0; i < width_; ++i )
        bits_->Set(lsb + i);
    }
  return *this;
  }

namespace probabilistic {

CounterVector& CounterVector::operator|=(const CounterVector& other)
{
  return Merge(other);
}

CounterVector operator|(const CounterVector& x, const CounterVector& y)
{
  CounterVector cv(x);
  return cv |= y;
}

}

bool CounterVector::Serialize(SerialInfo* info) const
  {
  return SerialObj::Serialize(info);
  }

CounterVector* CounterVector::Unserialize(UnserialInfo* info)
  {
  return reinterpret_cast<CounterVector*>(
      SerialObj::Unserialize(info, SER_COUNTERVECTOR));
  }

IMPLEMENT_SERIAL(CounterVector, SER_COUNTERVECTOR)

bool CounterVector::DoSerialize(SerialInfo* info) const
	{
	DO_SERIALIZE(SER_COUNTERVECTOR, SerialObj);
  if ( ! bits_->Serialize(info) )
    return false;
	return SERIALIZE(static_cast<uint64>(width_));
  }

bool CounterVector::DoUnserialize(UnserialInfo* info)
	{
	DO_UNSERIALIZE(SerialObj);
	bits_ = BitVector::Unserialize(info);
  if ( ! bits_ )
    return false;
  uint64 width;
  if ( ! UNSERIALIZE(&width) )
    return false;
	width_ = static_cast<size_t>(width);
	return true;
  }

